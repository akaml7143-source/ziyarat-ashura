const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");

initializeApp();

const OWNER_UID = "WvoTCtdUdYhbMluOwfwmBg6CJSL2";

exports.broadcastAppAnnouncement = onDocumentCreated(
  "app_updates/{announcementId}",
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
        android: { priority: "high" },
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
