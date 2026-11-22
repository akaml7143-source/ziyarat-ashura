const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");

initializeApp();

const OWNER_UID = "WvoTCtdUdYhbMluOwfwmBg6CJSL2";

exports.broadcastAppAnnouncement = onDocumentCreated(
  { document: "app_updates/{announcementId}", retry: true },
  async (event) => {
    const data = event.data?.data();
    if (!data || data.createdBy !== OWNER_UID) {
      logger.warn("Ignored announcement without the expected owner UID.");
      return;
    }

    const type = String(data.type || "message");
    const labels = {
      ar: {
        message: "رسالة من إدارة تطبيق زيارة عاشوراء",
        condolence: "تعزية من إدارة تطبيق زيارة عاشوراء",
        thanks: "شكر وتقدير من إدارة تطبيق زيارة عاشوراء",
      },
      fa: {
        message: "پیام مدیریت برنامه زیارت عاشورا",
        condolence: "پیام تسلیت مدیریت برنامه زیارت عاشورا",
        thanks: "سپاس و قدردانی مدیریت برنامه زیارت عاشورا",
      },
    };

    const sends = ["ar", "fa"].map(async (language) => {
      const title = String(data[language === "fa" ? "titleFa" : "titleAr"] || labels[language][type] || labels[language].message);
      const body = String(data[language === "fa" ? "bodyFa" : "bodyAr"] || "");
      if (!body) return null;

      return getMessaging().send({
        topic: `app_updates_${language}`,
        notification: { title, body },
        data: {
          kind: "announcement",
          announcementId: String(event.params.announcementId),
          type,
          language,
        },
        android: { priority: "high", notification: { channelId: "app_updates_v1" } },
      });
    });

    const results = await Promise.allSettled(sends);
    const failures = results.filter((result) => result.status === "rejected");
    if (failures.length) {
      logger.error("One or more announcement broadcasts failed.", failures);
      throw new Error("Announcement broadcast failed for one or more language topics.");
    }
    logger.info("Announcement broadcast sent to Arabic and Persian topics.", {
      announcementId: event.params.announcementId,
    });
  }
);


const db = getFirestore();
const GROUP_COOLDOWN_MS = 15 * 60 * 1000;

function requireGroupOwner(request) {
  if (request.auth?.uid !== OWNER_UID) {
    throw new HttpsError("permission-denied", "هذه العملية مخصصة لإدارة التطبيق.");
  }
}

function validateKhatmaInput(data) {
  const title = String(data.title || "").trim();
  const description = String(data.description || "").trim();
  const intentions = Array.isArray(data.intentions)
    ? [...new Set(data.intentions.map((value) => String(value).trim()).filter(Boolean))]
    : [];
  if (!title || title.length > 100) {
    throw new HttpsError("invalid-argument", "اسم الختمة مطلوب وبحد أقصى 100 حرف.");
  }
  if (description.length > 500) {
    throw new HttpsError("invalid-argument", "وصف الختمة طويل جداً.");
  }
  if (intentions.length < 1 || intentions.length > 20 || intentions.some((value) => value.length > 100)) {
    throw new HttpsError("invalid-argument", "أضف من نية واحدة إلى 20 نية، وبحد أقصى 100 حرف للنية.");
  }
  return { title, description, intentions };
}

exports.createGroupKhatma = onCall(async (request) => {
  requireGroupOwner(request);
  const data = validateKhatmaInput(request.data || {});
  const khatmaRef = db.collection("group_khatmas").doc();
  const statsRef = db.collection("group_khatma_stats").doc(khatmaRef.id);
  const globalRef = db.collection("group_khatma_stats").doc("global");
  const now = FieldValue.serverTimestamp();

  await db.runTransaction(async (tx) => {
    const globalSnap = await tx.get(globalRef);
    tx.create(khatmaRef, {
      ...data,
      status: "open",
      createdAt: now,
      updatedAt: now,
      createdBy: OWNER_UID,
    });
    tx.create(statsRef, {
      totalReadings: 0,
      totalParticipants: 0,
      intentionCounts: Object.fromEntries(data.intentions.map((item) => [item, 0])),
      updatedAt: now,
    });
    if (!globalSnap.exists) {
      tx.create(globalRef, { totalReadings: 0, totalParticipants: 0, updatedAt: now });
    }
  });
  return { khatmaId: khatmaRef.id };
});

exports.updateGroupKhatma = onCall(async (request) => {
  requireGroupOwner(request);
  const id = String(request.data?.khatmaId || "").trim();
  if (!id) throw new HttpsError("invalid-argument", "معرّف الختمة غير صالح.");
  const data = validateKhatmaInput(request.data || {});
  const khatmaRef = db.collection("group_khatmas").doc(id);
  const statsRef = db.collection("group_khatma_stats").doc(id);
  await db.runTransaction(async (tx) => {
    const [khatmaSnap, statsSnap] = await Promise.all([tx.get(khatmaRef), tx.get(statsRef)]);
    if (!khatmaSnap.exists || !statsSnap.exists) throw new HttpsError("not-found", "الختمة غير موجودة.");
    const oldCounts = statsSnap.data()?.intentionCounts || {};
    const nextCounts = { ...oldCounts };
    for (const item of data.intentions) {
      if (nextCounts[item] === undefined) nextCounts[item] = 0;
    }
    tx.update(khatmaRef, { ...data, updatedAt: FieldValue.serverTimestamp() });
    tx.update(statsRef, { intentionCounts: nextCounts, updatedAt: FieldValue.serverTimestamp() });
  });
  return { success: true };
});

exports.setGroupKhatmaStatus = onCall(async (request) => {
  requireGroupOwner(request);
  const id = String(request.data?.khatmaId || "").trim();
  const status = String(request.data?.status || "");
  if (!id || !["open", "paused", "archived"].includes(status)) {
    throw new HttpsError("invalid-argument", "بيانات حالة الختمة غير صالحة.");
  }
  const ref = db.collection("group_khatmas").doc(id);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "الختمة غير موجودة.");
  await ref.update({ status, updatedAt: FieldValue.serverTimestamp() });
  return { success: true };
});

exports.recordGroupKhatmaReading = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "يلزم تهيئة هوية المشاركة أولاً.");
  const id = String(request.data?.khatmaId || "").trim();
  const intention = String(request.data?.intention || "").trim();
  if (!id || !intention) throw new HttpsError("invalid-argument", "اختر الختمة والنية أولاً.");

  const khatmaRef = db.collection("group_khatmas").doc(id);
  const statsRef = db.collection("group_khatma_stats").doc(id);
  const globalRef = db.collection("group_khatma_stats").doc("global");
  const cooldownRef = db.collection("group_khatma_user_cooldowns").doc(uid);
  const khatmaParticipantRef = db.collection("group_khatma_participants").doc(id + "_" + uid);
  const globalParticipantRef = db.collection("group_khatma_global_participants").doc(uid);
  const recentRef = db.collection("group_khatma_recent_reads").doc();
  const now = Timestamp.now();

  await db.runTransaction(async (tx) => {
    const [khatmaSnap, statsSnap, globalSnap, cooldownSnap, kpSnap, gpSnap] =
      await Promise.all([
        tx.get(khatmaRef), tx.get(statsRef), tx.get(globalRef),
        tx.get(cooldownRef), tx.get(khatmaParticipantRef), tx.get(globalParticipantRef),
      ]);
    if (!khatmaSnap.exists || !statsSnap.exists || !globalSnap.exists) {
      throw new HttpsError("not-found", "الختمة غير موجودة أو لم تجهز بعد.");
    }
    const khatma = khatmaSnap.data();
    if (khatma.status !== "open") {
      throw new HttpsError("failed-precondition", "هذه الختمة لا تستقبل قراءات حالياً.");
    }
    if (!Array.isArray(khatma.intentions) || !khatma.intentions.includes(intention)) {
      throw new HttpsError("invalid-argument", "النية المختارة لا تتبع هذه الختمة.");
    }

    const last = cooldownSnap.data()?.lastRegisteredAt;
    if (last && typeof last.toMillis === "function") {
      const elapsed = now.toMillis() - last.toMillis();
      if (elapsed < GROUP_COOLDOWN_MS) {
        throw new HttpsError(
          "resource-exhausted",
          "يجب الانتظار 15 دقيقة بين كل تسجيل وآخر.",
          { retryAfterMs: GROUP_COOLDOWN_MS - elapsed },
        );
      }
    }

    const stats = statsSnap.data();
    const counts = { ...(stats.intentionCounts || {}) };
    counts[intention] = Number(counts[intention] || 0) + 1;
    tx.update(statsRef, {
      totalReadings: FieldValue.increment(1),
      totalParticipants: FieldValue.increment(kpSnap.exists ? 0 : 1),
      intentionCounts: counts,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.update(globalRef, {
      totalReadings: FieldValue.increment(1),
      totalParticipants: FieldValue.increment(gpSnap.exists ? 0 : 1),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(cooldownRef, { lastRegisteredAt: now });
    if (!kpSnap.exists) tx.create(khatmaParticipantRef, { joinedAt: now });
    if (!gpSnap.exists) tx.create(globalParticipantRef, { joinedAt: now });
    tx.create(recentRef, {
      khatmaId: id,
      intention,
      createdAt: now,
    });
  });

  return { success: true };
});
