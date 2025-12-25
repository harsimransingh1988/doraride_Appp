// functions/src/index.ts (GEN 2)

import { onRequest } from 'firebase-functions/v2/https';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler'; // 🆕 cron
import * as admin from 'firebase-admin';
import Stripe from 'stripe';
import * as nodemailer from 'nodemailer'; // 🆕 for support email

admin.initializeApp();
const db = admin.firestore();
const fcm = admin.messaging();

const stripe = new Stripe(process.env.STRIPE_SECRET as string, {
  apiVersion: '2024-06-20',
});

// 🆕 Support email constants + transporter
const SUPPORT_INBOX = 'support@doraride.com';
const SUPPORT_SMTP_USER = process.env.SUPPORT_SMTP_USER;
const SUPPORT_SMTP_PASS = process.env.SUPPORT_SMTP_PASS;

// If SMTP creds are not configured, mailTransport will be null and function will only log
const mailTransport = (SUPPORT_SMTP_USER && SUPPORT_SMTP_PASS)
  ? nodemailer.createTransport({
      service: 'gmail', // change to your provider if needed
      auth: {
        user: SUPPORT_SMTP_USER,
        pass: SUPPORT_SMTP_PASS,
      },
    })
  : null;

// 🆕 Use built-in fetch from Node 18+ runtime (typed loosely so TS doesn’t complain)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const gFetch: any = (globalThis as any).fetch;

// ---------------- CORS helper for HTTPS functions ----------------
const ALLOWED_ORIGINS = new Set<string>([
  'https://doraride.com',
  'https://doraride-af3ec.web.app',
  'http://localhost:5000',
  'http://127.0.0.1:5000',
  'http://localhost:5173',
  'http://127.0.0.1:5173',
]);

function applyCors(req: any, res: any): boolean {
  const origin = req.get?.('origin') ?? '';
  res.set('Vary', 'Origin');

  if (ALLOWED_ORIGINS.has(origin)) {
    res.set('Access-Control-Allow-Origin', origin);
  }
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return true;
  }
  return false;
}

// ---------------- createPaymentIntent (called from Flutter) ----------------
export const createPaymentIntent = onRequest(
  { region: 'us-central1', cpu: 1, secrets: ['STRIPE_SECRET'] },
  async (req, res) => {
    if (applyCors(req, res)) return;

    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    try {
      const body =
        typeof req.body === 'string' ? JSON.parse(req.body) : (req.body ?? {});
      const amount: number = Number(body.amount) || 0; // cents
      const currency: string = (body.currency || 'cad').toLowerCase();
      const description: string | undefined = body.description;
      const metadata: Record<string, string> | undefined = body.metadata;

      if (!Number.isFinite(amount) || amount <= 0) {
        res.status(400).json({ error: 'Invalid amount (cents required)' });
        return;
      }

      const pi = await stripe.paymentIntents.create({
        amount,
        currency,
        description,
        metadata,
        automatic_payment_methods: { enabled: true },
      });

      res.status(200).json({ clientSecret: pi.client_secret });
      return;
    } catch (err: any) {
      console.error('createPaymentIntent error:', err?.message, err);
      res.status(400).json({ error: err?.message ?? 'Unknown error' });
      return;
    }
  }
);

// ---------------- Stripe webhook (optional logging) ----------------
export const stripeWebhook = onRequest(
  { region: 'us-central1', cpu: 1, secrets: ['STRIPE_WEBHOOK_SECRET'] },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method not allowed');
      return;
    }

    const sig = req.get?.('stripe-signature') as string | undefined;
    if (!sig) {
      res.status(400).send('Missing stripe-signature header');
      return;
    }

    let event: Stripe.Event;
    try {
      const endpointSecret = process.env.STRIPE_WEBHOOK_SECRET as string;
      event = stripe.webhooks.constructEvent(req.rawBody, sig, endpointSecret);
    } catch (err: any) {
      console.error('Webhook signature verification failed:', err?.message);
      res.status(400).send(`Webhook Error: ${err?.message ?? 'verify failed'}`);
      return;
    }

    try {
      switch (event.type) {
        case 'payment_intent.succeeded': {
          const pi = event.data.object as Stripe.PaymentIntent;
          console.log('✅ payment_intent.succeeded', pi.id, pi.amount, pi.currency);
          break;
        }
        case 'payment_intent.payment_failed': {
          const pi = event.data.object as Stripe.PaymentIntent;
          console.log('❌ payment_intent.payment_failed', pi.id);
          break;
        }
        case 'checkout.session.completed': {
          const cs = event.data.object as Stripe.Checkout.Session;
          console.log(
            '🧾 checkout.session.completed',
            cs.id,
            cs.amount_total,
            cs.currency
          );
          break;
        }
        default:
          console.log('Unhandled event:', event.type);
      }
      res.status(200).send('OK');
      return;
    } catch (err: any) {
      console.error('stripeWebhook handler error:', err?.message, err);
      res.status(500).send('Internal error');
      return;
    }
  }
);

// ---------------- Firestore trigger: auto-refund on REJECT ----------------
export const handleBookingStatusChange = onDocumentUpdated(
  {
    region: 'us-central1',
    document: 'trips/{tripId}/booking_requests/{bookingId}',
    secrets: ['STRIPE_SECRET'], // needed so process.env.STRIPE_SECRET works here
  },
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after) return;

    const oldStatus = (before.get('status') ?? '').toString();
    const newStatus = (after.get('status') ?? '').toString();

    if (oldStatus === newStatus) return;

    // Only refund when moved to "rejected"
    if (newStatus !== 'rejected') {
      return;
    }

    const paymentIntentId = (after.get('paymentIntentId') ?? '').toString();
    if (!paymentIntentId) {
      console.log('No paymentIntentId on booking – cannot refund');
      return;
    }

    // avoid double-refunds
    const alreadyDone = after.get('refundStripeDone') === true;
    if (alreadyDone) {
      console.log('Refund already processed – skipping');
      return;
    }

    // amount in cents
    let amountCents = 0;
    const p = after.get('amountPaidNowCents');
    if (typeof p === 'number') {
      amountCents = p;
    }

    if (!Number.isFinite(amountCents) || amountCents <= 0) {
      console.log('No positive amount to refund – skipping');
      await after.ref.update({ refundStripeDone: true });
      return;
    }

    try {
      console.log(
        `Creating Stripe refund pi=${paymentIntentId}, amount=${amountCents}`
      );

      await stripe.refunds.create({
        payment_intent: paymentIntentId,
        amount: amountCents, // full refund
      });

      await after.ref.update({
        refundStripeDone: true,
        refundStripeAmountCents: amountCents,
        refundStripeAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log('✅ Stripe refund created successfully');
    } catch (err: any) {
      console.error('❌ Stripe refund failed:', err?.message, err);
      await after.ref.update({
        refundStripeDone: false,
        refundStripeError: err?.message ?? 'Refund failed',
      });
    }
  }
);

// -----------------------------------------------------------------------------
// Firestore trigger – when booking is COMPLETED, credit driver wallet
//  - ONLY if isFullPayment == true
// ----------------------------------------------------------------------------- 
export const handleBookingCompletionWallet = onDocumentUpdated(
  {
    region: 'us-central1',
    document: 'trips/{tripId}/booking_requests/{bookingId}',
  },
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after) return;

    const oldStatus = (before.get('status') ?? '').toString();
    const newStatus = (after.get('status') ?? '').toString();

    if (oldStatus === newStatus) return;

    // Only act when status moves to "completed"
    if (newStatus !== 'completed') {
      return;
    }

    // ✅ Only full online payments go to wallet
    const isFullPayment = after.get('isFullPayment') === true;
    if (!isFullPayment) {
      console.log(
        'Booking completed but was deposit-only, no wallet credit (platform fee only).'
      );
      return;
    }

    // avoid double-credit
    const alreadyCredited = after.get('walletCredited') === true;
    if (alreadyCredited) {
      console.log('Wallet already credited for this booking – skipping');
      return;
    }

    const driverId = (after.get('driverId') ?? '').toString();
    if (!driverId) {
      console.log('No driverId on booking – cannot credit wallet');
      return;
    }

    // fullTotal stored in CAD (double)
    const fullTotal = Number(after.get('fullTotal') ?? 0);
    if (!Number.isFinite(fullTotal) || fullTotal <= 0) {
      console.log('Invalid fullTotal on booking – skipping wallet credit');
      return;
    }

    const grossCents = Math.round(fullTotal * 100);
    const platformFeeCents = Math.round(grossCents * 0.10); // 10%
    const driverNetCents = grossCents - platformFeeCents;

    if (driverNetCents <= 0) {
      console.log('Driver net <= 0 – skipping wallet credit');
      return;
    }

    const tripId = event.params.tripId as string;
    const bookingId = event.params.bookingId as string;

    const walletRef = db
      .collection('users')
      .doc(driverId)
      .collection('wallet')
      .doc('main');

    const txnsCol = db
      .collection('users')
      .doc(driverId)
      .collection('wallet_transactions');

    try {
      await db.runTransaction(async (tx) => {
        const walletSnap = await tx.get(walletRef);
        let currentBalance = 0;
        if (walletSnap.exists) {
          const bal = walletSnap.get('balanceCents');
          if (typeof bal === 'number') currentBalance = bal;
        }

        const newBalance = currentBalance + driverNetCents;

        tx.set(
          walletRef,
          {
            balanceCents: newBalance,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        const txnRef = txnsCol.doc();
        tx.set(txnRef, {
          id: txnRef.id,
          type: 'ridePayment',
          amountCents: driverNetCents,
          grossAmountCents: grossCents,
          platformFeeCents,
          status: 'success',
          note: 'Trip completed payout (full online payment, 90% net)',
          tripId,
          bookingId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // mark booking as credited
        tx.update(after.ref, {
          walletCredited: true,
          walletCreditedAt: admin.firestore.FieldValue.serverTimestamp(),
          walletDriverNetCents: driverNetCents,
          walletPlatformFeeCents: platformFeeCents,
        });
      });

      console.log(
        `✅ Wallet credited (FULL payment) driver=${driverId}, booking=${bookingId}, net=${driverNetCents} cents, fee=${platformFeeCents} cents`
      );
    } catch (err: any) {
      console.error('❌ Wallet credit failed:', err?.message, err);
    }
  }
);

/* ============================================================================
 *  PUSH NOTIFICATIONS – DoraRide app activity
 *  Requires: users/{uid}.fcmTokens[] written by your Flutter app.
 * ========================================================================== */

async function getUserTokens(userId: string | undefined): Promise<string[]> {
  if (!userId) return [];
  const snap = await db.collection('users').doc(userId).get();
  if (!snap.exists) return [];

  const data = snap.data() as any;
  const out = new Set<string>();

  // Preferred: array of tokens
  if (Array.isArray(data.fcmTokens)) {
    for (const t of data.fcmTokens) {
      if (typeof t === 'string' && t.trim()) {
        out.add(t.trim());
      }
    }
  }

  // Legacy / single fields
  if (typeof data.fcm_token === 'string' && data.fcm_token.trim()) {
    out.add(data.fcm_token.trim());
  }
  if (typeof data.fcmToken === 'string' && data.fcmToken.trim()) {
    out.add(data.fcmToken.trim());
  }

  return Array.from(out);
}

async function sendPushToTokens(
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string> = {}
) {
  if (!tokens.length) return;

  const payload: admin.messaging.MessagingPayload = {
    notification: { title, body },
    data,
  };

  const response = await fcm.sendToDevice(tokens, payload, {
    priority: 'high',
  });

  console.log(
    `🔔 Sent push "${title}" to ${tokens.length} tokens. success=${response.successCount}, fail=${response.failureCount}`
  );
}

// -----------------------------------------------------------------------------
// 1) Rider creates booking request → notify DRIVER
// -----------------------------------------------------------------------------
export const notifyDriverOnBookingCreated = onDocumentCreated(
  {
    region: 'us-central1',
    document: 'trips/{tripId}/booking_requests/{bookingId}',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as any;
    const tripId = event.params.tripId as string;

    try {
      const tripSnap = await db.collection('trips').doc(tripId).get();
      if (!tripSnap.exists) {
        console.log('Trip not found for booking', tripId);
        return;
      }

      const trip = tripSnap.data() as any;
      const driverId = trip.driverId as string | undefined;
      const origin = (trip.origin ?? '') as string;
      const destination = (trip.destination ?? '') as string;

      if (!driverId) {
        console.log('No driverId on trip, skipping notifyDriverOnBookingCreated');
        return;
      }

      const riderName = (data.riderName ?? 'New rider') as string;

      // ------------------------------
      // SAVE IN-APP NOTIFICATION (BELL)
      // ------------------------------
      await db
        .collection('users')
        .doc(driverId)
        .collection('notifications')
        .add({
          title: 'New booking request',
          body: `${riderName} requested a seat on your trip ${origin} → ${destination}.`,
          type: 'booking_request',
          tripId,
          bookingId: event.params.bookingId as string,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      const tokens = await getUserTokens(driverId);
      if (!tokens.length) {
        console.log('No tokens for driver', driverId);
        return;
      }

      await sendPushToTokens(
        tokens,
        'New booking request',
        `${riderName} requested a seat on your trip ${origin} → ${destination}.`,
        {
          type: 'booking_request',
          tripId,
          bookingId: event.params.bookingId as string,
        }
      );
    } catch (err) {
      console.error('notifyDriverOnBookingCreated error:', err);
    }
  }
);

// -----------------------------------------------------------------------------
// 2) Booking status changed → notify RIDER
// -----------------------------------------------------------------------------
export const notifyRiderOnBookingStatusChange = onDocumentUpdated(
  {
    region: 'us-central1',
    document: 'trips/{tripId}/booking_requests/{bookingId}',
  },
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after) return;

    const oldStatus = (before.get('status') ?? '').toString();
    const newStatus = (after.get('status') ?? '').toString();
    if (!newStatus || oldStatus === newStatus) return;

    const tripId = event.params.tripId as string;
    const bookingId = event.params.bookingId as string;

    try {
      const riderId = (after.get('riderId') ?? '').toString();
      if (!riderId) {
        console.log('No riderId on booking, skipping notifyRiderOnBookingStatusChange');
        return;
      }

      const tokens = await getUserTokens(riderId);
      if (!tokens.length) {
        console.log('No tokens for rider', riderId);
        return;
      }

      const tripSnap = await db.collection('trips').doc(tripId).get();
      const trip = tripSnap.data() as any | undefined;
      const origin = trip?.origin ?? '';
      const destination = trip?.destination ?? '';

      let title = 'Booking update';
      let body = `Your booking on ${origin} → ${destination} is now ${newStatus}.`;

      if (newStatus === 'accepted') {
        title = 'Booking accepted 🎉';
        body = `Driver accepted your booking on ${origin} → ${destination}.`;
      } else if (newStatus === 'rejected' || newStatus === 'declined') {
        title = 'Booking declined';
        body = `Driver declined your booking on ${origin} → ${destination}.`;
      } else if (newStatus === 'completed') {
        title = 'Trip completed';
        body = `Your trip ${origin} → ${destination} is completed.`;
      }

      // ------------------------------
      // SAVE IN-APP NOTIFICATION (BELL)
      // ------------------------------
      await db
        .collection('users')
        .doc(riderId)
        .collection('notifications')
        .add({
          title,
          body,
          type: 'booking_status',
          status: newStatus,
          tripId,
          bookingId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      await sendPushToTokens(tokens, title, body, {
        type: 'booking_status',
        tripId,
        bookingId,
        status: newStatus,
      });
    } catch (err) {
      console.error('notifyRiderOnBookingStatusChange error:', err);
    }
  }
);

// -----------------------------------------------------------------------------
// 3) Trip cancelled → notify all riders with ACCEPTED bookings
// -----------------------------------------------------------------------------
export const notifyRidersOnTripCancelled = onDocumentUpdated(
  {
    region: 'us-central1',
    document: 'trips/{tripId}',
  },
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after) return;

    const oldStatus = (before.get('status') ?? '').toString();
    const newStatus = (after.get('status') ?? '').toString();

    if (oldStatus === newStatus) return;
    if (newStatus !== 'cancelled' && newStatus !== 'canceled') return;

    const tripId = event.params.tripId as string;
    const origin = (after.get('origin') ?? '') as string;
    const destination = (after.get('destination') ?? '') as string;

    try {
      const acceptedSnap = await db
        .collection('trips')
        .doc(tripId)
        .collection('booking_requests')
        .where('status', '==', 'accepted')
        .get();

      const riderIds = new Set<string>();
      acceptedSnap.forEach((doc) => {
        const d = doc.data() as any;
        if (d.riderId) {
          riderIds.add(d.riderId.toString());
        }
      });

      for (const riderId of riderIds) {
        const tokens = await getUserTokens(riderId);
        if (!tokens.length) continue;

        const title = 'Trip cancelled';
        const body = `Your trip ${origin} → ${destination} has been cancelled by the driver.`;

        // ------------------------------
        // SAVE IN-APP NOTIFICATION (BELL)
        // ------------------------------
        await db
          .collection('users')
          .doc(riderId)
          .collection('notifications')
          .add({
            title,
            body,
            type: 'trip_cancelled',
            tripId,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

        await sendPushToTokens(
          tokens,
          title,
          body,
          {
            type: 'trip_cancelled',
            tripId,
          }
        );
      }
    } catch (err) {
      console.error('notifyRidersOnTripCancelled error:', err);
    }
  }
);

// -----------------------------------------------------------------------------
// 4) Chat message created → notify the OTHER user
//    Assumes chats/{chatId}/messages/{messageId} with senderId + receiverId.
// -----------------------------------------------------------------------------
export const notifyOnChatMessageCreated = onDocumentCreated(
  {
    region: 'us-central1',
    document: 'chats/{chatId}/messages/{messageId}',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as any;
    const senderId = (data.senderId ?? '').toString();
    const receiverId = (data.receiverId ?? '').toString();

    if (!receiverId || !senderId || senderId === receiverId) return;

    try {
      const tokens = await getUserTokens(receiverId);
      if (!tokens.length) {
        console.log('No tokens for chat receiver', receiverId);
        return;
      }

      const text = (data.text ?? 'New message') as string;
      const shortText =
        text.length > 80 ? text.substring(0, 77) + '...' : text;

      // ------------------------------
      // SAVE IN-APP NOTIFICATION (BELL)
      // ------------------------------
      await db
        .collection('users')
        .doc(receiverId)
        .collection('notifications')
        .add({
          title: 'New message',
          body: shortText,
          type: 'chat_message',
          chatId: event.params.chatId as string,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      await sendPushToTokens(
        tokens,
        'New message',
        shortText,
        {
          type: 'chat_message',
          chatId: event.params.chatId as string,
        }
      );
    } catch (err) {
      console.error('notifyOnChatMessageCreated error:', err);
    }
  }
);

// -----------------------------------------------------------------------------
// 5) 🆕 Support ticket created → send email to support@doraride.com
//    Triggered by: Flutter HelpPage writing to support_tickets
// -----------------------------------------------------------------------------
export const sendSupportTicketEmail = onDocumentCreated(
  {
    region: 'us-central1',
    document: 'support_tickets/{ticketId}',
    // make sure these secrets exist so process.env has values
    secrets: ['SUPPORT_SMTP_USER', 'SUPPORT_SMTP_PASS'],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as any;
    const ticketId = event.params.ticketId as string;

    const subject = (data.subject ?? 'New Support Request') as string;
    const details = (data.details ?? '') as string;
    const fromEmail = (data.fromEmail ?? 'unknown@user') as string;
    const userId = (data.userId ?? 'anonymous') as string;
    const userName = (data.userName ?? 'Unknown User') as string;

    let createdAt: Date;
    const ts = data.createdAt;
    if (ts instanceof admin.firestore.Timestamp) {
      createdAt = ts.toDate();
    } else {
      createdAt = new Date();
    }

    // If transporter is not configured, just log and mark on doc
    if (!mailTransport) {
      console.warn(
        'sendSupportTicketEmail: mailTransport is not configured (missing SUPPORT_SMTP_USER / SUPPORT_SMTP_PASS).'
      );
      await snap.ref.set(
        {
          emailSent: false,
          emailError: 'SMTP not configured (SUPPORT_SMTP_USER / SUPPORT_SMTP_PASS missing)',
        },
        { merge: true }
      );
      return;
    }

    const mailOptions: nodemailer.SendMailOptions = {
      from: `"DoraRide Support Bot" <${SUPPORT_SMTP_USER || SUPPORT_INBOX}>`,
      to: SUPPORT_INBOX,
      subject: `DoraRide Support: ${subject} (Ticket ${ticketId})`,
      text: `
New support ticket in DoraRide:

Ticket ID: ${ticketId}
Created At: ${createdAt.toISOString()}

From: ${userName} (${fromEmail})
User ID: ${userId}

Subject: ${subject}

Details:
${details}
      `.trim(),
      html: `
        <h2>New DoraRide Support Ticket</h2>
        <p><strong>Ticket ID:</strong> ${ticketId}</p>
        <p><strong>Created At:</strong> ${createdAt.toISOString()}</p>
        <hr/>
        <p><strong>From:</strong> ${userName} (${fromEmail})</p>
        <p><strong>User ID:</strong> ${userId}</p>
        <hr/>
        <p><strong>Subject:</strong> ${subject}</p>
        <p><strong>Details:</strong></p>
        <pre style="white-space:pre-wrap;font-family:system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;">
${details}
        </pre>
      `,
    };

    try {
      await mailTransport.sendMail(mailOptions);

      await snap.ref.set(
        {
          emailSent: true,
          emailSentAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      console.log(`✅ Support email sent for ticket ${ticketId}`);
    } catch (err: any) {
      console.error('❌ Error sending support email:', err?.message || err);

      await snap.ref.set(
        {
          emailSent: false,
          emailError: err?.message || String(err),
        },
        { merge: true }
      );
    }
  }
);

/* =============================================================================
 * 🆕 AUTO-START + AUTO-COMPLETE TRIPS
 *  - Uses: trips.date (Timestamp, full departure datetime)
 *  - Uses: trips.autoStatus, startedAt, completedAt (from Flutter model)
 *  - Also writes distance / ETA from Google Directions API.
 *  - NOTE: does NOT touch or change any existing logic above.
 * ========================================================================== */

// helper to safely get a Timestamp as Date
function tsToDate(value: any | undefined): Date | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  return null;
}

// -----------------------------------------------------------------------------
// A) When a trip is created → call Google Directions to store distance + ETA
//    Fields added on trips/{tripId}:
//      - distanceMeters: number
//      - estimatedDurationSeconds: number
//      - estimatedArrivalTime: Timestamp (departure + duration)
//      - autoStatus: defaults to 'scheduled' if missing
// -----------------------------------------------------------------------------
export const updateTripDistanceAndEta = onDocumentCreated(
  {
    region: 'us-central1',
    document: 'trips/{tripId}',
    secrets: ['GOOGLE_MAPS_API_KEY'],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as any;
    const tripRef = snap.ref;

    const origin = (data.origin ?? '').toString().trim();
    const destination = (data.destination ?? '').toString().trim();
    const departureTs = data.date as admin.firestore.Timestamp | undefined;

    if (!origin || !destination) {
      console.log('updateTripDistanceAndEta: missing origin/destination – skipping');
      return;
    }

    const apiKey = process.env.GOOGLE_MAPS_API_KEY;
    if (!apiKey) {
      console.warn('updateTripDistanceAndEta: GOOGLE_MAPS_API_KEY not configured – skipping');
      return;
    }

    if (!gFetch) {
      console.warn('updateTripDistanceAndEta: fetch not available in runtime – skipping');
      return;
    }

    try {
      const params = new URLSearchParams({
        origin,
        destination,
        key: apiKey,
        mode: 'driving',
      });

      const url = `https://maps.googleapis.com/maps/api/directions/json?${params.toString()}`;
      const res = await gFetch(url);
      if (!res.ok) {
        console.warn('Directions API HTTP error', res.status, await res.text());
        return;
      }

      const json = await res.json();
      const routes = json.routes;
      if (!Array.isArray(routes) || !routes.length) {
        console.warn('Directions API: no routes for trip', tripRef.id);
        return;
      }

      const legs = routes[0]?.legs;
      if (!Array.isArray(legs) || !legs.length) {
        console.warn('Directions API: no legs for trip', tripRef.id);
        return;
      }

      const leg = legs[0];
      const distanceValue = leg.distance?.value;
      const durationValue = leg.duration?.value;

      if (typeof distanceValue !== 'number' || typeof durationValue !== 'number') {
        console.warn('Directions API: missing distance/duration for trip', tripRef.id);
        return;
      }

      const departureDate = tsToDate(departureTs) ?? new Date();
      const etaMs = departureDate.getTime() + durationValue * 1000;
      const eta = new Date(etaMs);

      const updates: Record<string, any> = {
        distanceMeters: distanceValue,
        estimatedDurationSeconds: durationValue,
        estimatedArrivalTime: admin.firestore.Timestamp.fromDate(eta),
      };

      // Ensure autoStatus has a default if it's missing
      if (!data.autoStatus) {
        updates.autoStatus = 'scheduled';
      }

      await tripRef.set(updates, { merge: true });

      console.log(
        `✅ updateTripDistanceAndEta: trip=${tripRef.id}, distance=${distanceValue}m, duration=${durationValue}s`
      );
    } catch (err: any) {
      console.error('❌ updateTripDistanceAndEta error:', err?.message || err);
    }
  }
);

// -----------------------------------------------------------------------------
// B) Cron: every 5 minutes → move due trips from `scheduled` → `ongoing`
//    - Reads trips where autoStatus == 'scheduled' and date <= now
//    - Sets: autoStatus='ongoing', startedAt=serverTimestamp()
//    - Also mirrors same fields into trips_live/{tripId} (merge)
// -----------------------------------------------------------------------------
export const autoStartTrips = onSchedule(
  {
    region: 'us-central1',
    schedule: 'every 5 minutes',
  },
  async () => {
    const nowTs = admin.firestore.Timestamp.now();

    const snap = await db
      .collection('trips')
      .where('autoStatus', '==', 'scheduled')
      .where('date', '<=', nowTs)
      .limit(100)
      .get();

    if (snap.empty) {
      console.log('autoStartTrips: no trips to start');
      return;
    }

    console.log(`autoStartTrips: found ${snap.size} trips to move to ongoing`);

    const startedAt = admin.firestore.FieldValue.serverTimestamp();

    const batch = db.batch();

    for (const doc of snap.docs) {
      const tripId = doc.id;

      batch.update(doc.ref, {
        autoStatus: 'ongoing',
        startedAt,
      });

      const liveRef = db.collection('trips_live').doc(tripId);
      batch.set(
        liveRef,
        {
          autoStatus: 'ongoing',
          startedAt,
        },
        { merge: true }
      );
    }

    await batch.commit();
    console.log('autoStartTrips: updated trips to ongoing');
  }
);

// -----------------------------------------------------------------------------
// C) Cron: every 5 minutes → auto-complete trips
//
//    - Picks trips where:
//        autoStatus == 'ongoing'
//      AND
//        (estimatedArrivalTime <= now) OR
//        (no ETA but date <= now - fallbackBuffer)
//    - Then:
//        * updates trips/{tripId}:
//            autoStatus='completed'
//            completedAt=serverTimestamp()
//            status='completed'
//            autoCompletedTrip=true
//        * updates trips_live/{tripId} similarly
//        * sets all ACCEPTED booking_requests to status='completed'
//          with autoCompleted=true (fires wallet trigger)
// -----------------------------------------------------------------------------
export const autoCompleteTrips = onSchedule(
  {
    region: 'us-central1',
    schedule: 'every 5 minutes',
  },
  async () => {
    const nowTs = admin.firestore.Timestamp.now();
    const nowMs = nowTs.toMillis();

    // Fallback: if no ETA, consider trip done 3 hours after departure
    const fallbackBufferMs = 3 * 60 * 60 * 1000;

    const snap = await db
      .collection('trips')
      .where('autoStatus', '==', 'ongoing')
      .limit(100)
      .get();

    if (snap.empty) {
      console.log('autoCompleteTrips: no ongoing trips to inspect');
      return;
    }

    console.log(`autoCompleteTrips: inspecting ${snap.size} ongoing trips`);

    for (const doc of snap.docs) {
      const data = doc.data() as any;
      const tripId = doc.id;

      const etaTs = data.estimatedArrivalTime as admin.firestore.Timestamp | undefined;
      const depTs = data.date as admin.firestore.Timestamp | undefined;

      let shouldComplete = false;

      if (etaTs instanceof admin.firestore.Timestamp) {
        if (etaTs.toMillis() <= nowMs) {
          shouldComplete = true;
        }
      } else if (depTs instanceof admin.firestore.Timestamp) {
        if (depTs.toMillis() + fallbackBufferMs <= nowMs) {
          shouldComplete = true;
        }
      }

      if (!shouldComplete) {
        continue;
      }

      console.log(`autoCompleteTrips: completing trip ${tripId}`);

      const completedAt = admin.firestore.FieldValue.serverTimestamp();

      // 1) Update trip + live trip
      const tripUpdate: Record<string, any> = {
        autoStatus: 'completed',
        completedAt,
        status: 'completed',
        autoCompletedTrip: true,
      };

      const liveRef = db.collection('trips_live').doc(tripId);

      const batch = db.batch();
      batch.update(doc.ref, tripUpdate);
      batch.set(
        liveRef,
        {
          autoStatus: 'completed',
          completedAt,
          status: 'completed',
        },
        { merge: true }
      );
      await batch.commit();

      // 2) Mark accepted bookings as completed (will trigger wallet logic)
      const bookingsSnap = await doc.ref
        .collection('booking_requests')
        .where('status', '==', 'accepted')
        .get();

      if (bookingsSnap.empty) {
        console.log(`autoCompleteTrips: no accepted bookings for trip ${tripId}`);
        continue;
      }

      const bookingsBatch = db.batch();
      for (const b of bookingsSnap.docs) {
        bookingsBatch.update(b.ref, {
          status: 'completed',
          autoCompleted: true,
          completedAt,
        });
      }
      await bookingsBatch.commit();

      console.log(
        `autoCompleteTrips: trip ${tripId} completed with ${bookingsSnap.size} bookings auto-marked completed`
      );
    }
  }
);
