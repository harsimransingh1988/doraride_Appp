// functions/index.js
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Stripe from "stripe";

// Read secret from Firebase Secret Manager
const STRIPE_SECRET = defineSecret("STRIPE_SECRET");

// Helper: add CORS headers on every response
function addCors(res) {
  res.set("Access-Control-Allow-Origin", "*");              // allow localhost + prod
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS"); // what we accept
  res.set("Access-Control-Allow-Headers", "Content-Type");  // what we accept
}

export const createPaymentIntent = onRequest(
  { region: "us-central1", secrets: [STRIPE_SECRET] },
  async (req, res) => {
    // Always set CORS headers
    addCors(res);

    // Handle the preflight
    if (req.method === "OPTIONS") {
      res.status(204).send(""); // no content
      return;
    }

    try {
      if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
      }

      const { amount, currency, metadata } = req.body || {};
      const cents = Math.round(Number(amount) || 0);
      if (!cents || cents <= 0) {
        res.status(400).json({ error: "Invalid amount" });
        return;
      }

      const stripe = new Stripe(STRIPE_SECRET.value(), {
        apiVersion: "2024-06-20",
      });

      const intent = await stripe.paymentIntents.create({
        amount: cents,
        currency: (currency || "CAD").toLowerCase(),
        automatic_payment_methods: { enabled: true },
        metadata: metadata || {},
      });

      res.status(200).json({ clientSecret: intent.client_secret });
    } catch (err) {
      console.error("createPaymentIntent error:", err);
      res.status(500).json({ error: err.message || "Server error" });
    }
  }
);
