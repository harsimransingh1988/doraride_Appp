// web/firebase-messaging-sw.js

// Use compat version because firebase_messaging for web still uses it under the hood
importScripts("https://www.gstatic.com/firebasejs/9.6.11/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.6.11/firebase-messaging-compat.js");

// EXACTLY the same config as in firebase_options.dart (web)
firebase.initializeApp({
  apiKey: "AIzaSyDJWu_E1ar-YuTn418J3MxL5oANY6cP56M",
  authDomain: "doraride-af3ec.firebaseapp.com",
  projectId: "doraride-af3ec",
  storageBucket: "doraride-af3ec.firebasestorage.app",
  messagingSenderId: "370934169599",
  appId: "1:370934169599:web:b0b9c7d9d1b79dd1cf71ca",
});

// Optional: show background notifications
const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
  const notificationTitle =
    (payload.notification && payload.notification.title) || "DoraRide";
  const notificationOptions = {
    body: (payload.notification && payload.notification.body) || "",
    icon: "/icons/Icon-192.png",
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
