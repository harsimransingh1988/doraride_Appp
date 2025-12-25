// functions/src/index.ts
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import Stripe from "stripe";

admin.initializeApp();

// ======================= STRIPE SETUP =======================
const stripe = new Stripe(process.env.STRIPE_SECRET as string, {
  apiVersion: "2024-06-20",
});

// ---------- CORS helper ----------
const ALLOWED_ORIGINS = new Set<string>([
  "https://doraride-af3ec.web.app",
  "http://localhost:5000",
  "http://127.0.0.1:5000",
  "http://localhost:5173",
  "http://127.0.0.1:5173",
]);

function applyCors(req: functions.Request, res: functions.Response): boolean {
  const origin = req.headers.origin ?? "";
  if (ALLOWED_ORIGINS.has(origin)) {
    res.set("Access-Control-Allow-Origin", origin);
  }
  res.set("Access-Control-Allow-Headers", "Content-Type");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");

  if (req.method === "OPTIONS") {
    res.status(204).end();
    return true;
  }
  return false;
}

// ---------- Create PaymentIntent (called by your app) ----------
export const createPaymentIntent = functions
  .region("us-central1")
  .runWith({ secrets: ["STRIPE_SECRET"] })
  .https.onRequest(async (req, res) => {
    // CORS preflight
    if (applyCors(req, res)) return;

    if (req.method !== "POST") {
      return res.status(405).json({ error: "Method not allowed" });
    }

    try {
      const body =
        typeof req.body === "string"
          ? JSON.parse(req.body)
          : (req.body as any) ?? {};

      const amount = Number(body.amount) || 0;
      const currency = (body.currency || "cad").toLowerCase();
      const description = body.description as string | undefined;
      const metadata = body.metadata as Record<string, string> | undefined;

      if (!Number.isFinite(amount) || amount <= 0) {
        return res
          .status(400)
          .json({ error: "Invalid amount (cents required)" });
      }

      const paymentIntent = await stripe.paymentIntents.create({
        amount,
        currency,
        description,
        metadata,
        automatic_payment_methods: { enabled: true },
      });

      return res.status(200).json({
        clientSecret: paymentIntent.client_secret,
      });
    } catch (err: any) {
      const message = err?.message ?? "Unknown error";
      console.error("createPaymentIntent error:", message, err);
      return res.status(400).json({ error: message });
    }
  });

// ---------- Stripe Webhook (server-to-server) ----------
export const stripeWebhook = functions
  .region("us-central1")
  .runWith({ secrets: ["STRIPE_WEBHOOK_SECRET"] })
  .https.onRequest(async (req, res) => {
    // Do NOT run CORS here: Stripe posts directly from Stripe servers
    if (req.method !== "POST") {
      return res.status(405).send("Method not allowed");
    }

    const sig = (req.headers["stripe-signature"] as string | undefined) ?? undefined;
    if (!sig) {
      return res.status(400).send("Missing stripe-signature header");
    }

    let event: Stripe.Event;
    try {
      const endpointSecret = process.env.STRIPE_WEBHOOK_SECRET as string;
      event = stripe.webhooks.constructEvent(req.rawBody, sig, endpointSecret);
    } catch (err: any) {
      console.error(
        "Webhook signature verification failed:",
        err?.message
      );
      return res
        .status(400)
        .send(`Webhook Error: ${err?.message ?? "verify failed"}`);
    }

    try {
      // Handle the events you care about
      switch (event.type) {
        case "payment_intent.succeeded": {
          const pi = event.data.object as Stripe.PaymentIntent;
          console.log(
            "✅ payment_intent.succeeded",
            pi.id,
            pi.amount,
            pi.currency
          );
          // TODO: mark booking paid in Firestore using pi.metadata.* if you added ids
          break;
        }
        case "payment_intent.payment_failed": {
          const pi = event.data.object as Stripe.PaymentIntent;
          console.log("❌ payment_intent.failed", pi.id);
          break;
        }
        case "checkout.session.completed": {
          const cs = event.data.object as Stripe.Checkout.Session;
          console.log(
            "🧾 checkout.session.completed",
            cs.id,
            cs.amount_total,
            cs.currency
          );
          // TODO: same—update booking/trip based on cs.metadata
          break;
        }
        default: {
          console.log("Unhandled event:", event.type);
        }
      }

      return res.status(200).send("OK");
    } catch (err: any) {
      console.error(
        "stripeWebhook handler error:",
        err?.message,
        err
      );
      return res.status(500).send("Internal error");
    }
  });

// =======================================================
// ===============  NOTIFICATIONS LOGIC  =================
// =======================================================

const db = admin.firestore();

interface NotificationPayload {
  title: string;
  body: string;
  type?: string;
  extraData?: Record<string, unknown>;
}

/**
 * Get all FCM tokens for a user from:
 *  - users/{uid}.fcmToken (string)
 *  - users/{uid}.fcmTokens (string[])
 */
async function getUserFcmTokens(uid: string): Promise<string[]> {
  const doc = await db.collection("users").doc(uid).get();
  if (!doc.exists) return [];

  const data = doc.data() ?? {};
  const tokens = new Set<string>();

  const single = (data as any).fcmToken;
  if (typeof single === "string" && single.trim()) {
    tokens.add(single.trim());
  }

  const arr = (data as any).fcmTokens;
  if (Array.isArray(arr)) {
    for (const t of arr) {
      if (typeof t === "string" && t.trim()) {
        tokens.add(t.trim());
      }
    }
  }

  return Array.from(tokens);
}

/**
 * Create Firestore notification under:
 *  users/{uid}/notifications/{autoId}
 */
async function createNotification(
  uid: string,
  data: NotificationPayload
): Promise<NotificationPayload & { data: Record<string, unknown> }> {
  const payload = {
    title: data.title || "DoraRide",
    body: data.body || "",
    type: data.type || "general",
    data: data.extraData || {},
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await db
    .collection("users")
    .doc(uid)
    .collection("notifications")
    .add(payload);

  return payload;
}

/**
 * Send push notification via FCM to all user's tokens.
 */
async function sendPushToUser(
  uid: string,
  payload: NotificationPayload & { data: Record<string, unknown> }
): Promise<void> {
  const tokens = await getUserFcmTokens(uid);
  if (!tokens.length) {
    console.log("No FCM tokens for user", uid);
    return;
  }

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: {
      type: payload.type || "general",
      ...Object.entries(payload.data || {}).reduce<Record<string, string>>(
        (acc, [k, v]) => {
          acc[k] = v == null ? "" : String(v);
          return acc;
        },
        {}
      ),
    },
  };

  const res = await admin.messaging().sendEachForMulticast(message);
  console.log(
    "sendPushToUser:",
    uid,
    "success:",
    res.successCount,
    "fail:",
    res.failureCount
  );
}

// ---------- 1) Booking request created -> notify driver ----------
export const onBookingRequestCreated = functions.firestore
  .document("trips/{tripId}/booking_requests/{bookingId}")
  .onCreate(async (snap, context) => {
    const data = snap.data() as any;
    const tripId = context.params.tripId as string;

    const driverId = data.driverId as string | undefined;
    const riderId = data.riderId as string | undefined;
    const seats = data.seats as number | undefined;

    if (!driverId) {
      console.log("onBookingRequestCreated: missing driverId", snap.id);
      return;
    }

    const riderName = (data.riderName as string | undefined) || "A rider";

    const notif = await createNotification(driverId, {
      title: "New booking request",
      body: `${riderName} requested ${seats || 1} seat(s).`,
      type: "booking_request",
      extraData: {
        bookingId: snap.id,
        tripId,
        riderId: riderId || "",
      },
    });

    await sendPushToUser(driverId, notif);
  });

// ---------- 2) Booking status changed -> notify rider ----------
export const onBookingStatusChanged = functions.firestore
  .document("trips/{tripId}/booking_requests/{bookingId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() as any;
    const after = change.after.data() as any;

    if (!before || !after) return;
    if (before.status === after.status) return;

    const tripId = context.params.tripId as string;
    const bookingId = context.params.bookingId as string;

    const riderId = after.riderId as string | undefined;
    if (!riderId) {
      console.log("onBookingStatusChanged: no riderId", bookingId);
      return;
    }

    const driverName = (after.driverName as string | undefined) || "Driver";

    let title: string;
    let body: string;
    let type: string;

    if (after.status === "accepted") {
      title = "Booking accepted 🎉";
      body = `${driverName} accepted your booking request.`;
      type = "booking_accepted";
    } else if (after.status === "rejected") {
      title = "Booking rejected";
      body = `${driverName} rejected your booking request.`;
      type = "booking_rejected";
    } else {
      // ignore other status changes
      return;
    }

    const notif = await createNotification(riderId, {
      title,
      body,
      type,
      extraData: {
        bookingId,
        tripId,
        driverId: after.driverId || "",
      },
    });

    await sendPushToUser(riderId, notif);
  });

// ---------- 3) New chat message -> notify other participant(s) ----------
export const onNewMessage = functions.firestore
  .document("conversations/{conversationId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const msg = snap.data() as any;
    const conversationId = context.params.conversationId as string;

    const senderId = msg.senderId as string | undefined;
    const text: string =
      msg.text || msg.body || "";

    // Load conversation doc to find participants
    const convSnap = await db.collection("conversations").doc(conversationId).get();
    const conv = (convSnap.data() as any) ?? {};
    const participants: string[] = Array.isArray(conv.participants)
      ? conv.participants
      : [];

    if (!participants.length || !senderId) {
      console.log("onNewMessage: missing participants or senderId");
      return;
    }

    const otherIds = participants.filter((id) => id && id !== senderId);
    if (!otherIds.length) {
      console.log("onNewMessage: no other participants");
      return;
    }

    const notifTitle = "New message";
    const notifBody = text ? String(text).slice(0, 80) : "You have a new message.";

    await Promise.all(
      otherIds.map(async (uid) => {
        const notif = await createNotification(uid, {
          title: notifTitle,
          body: notifBody,
          type: "message",
          extraData: {
            conversationId,
            messageId: snap.id,
            senderId,
          },
        });

        await sendPushToUser(uid, notif);
      })
    );
  });
