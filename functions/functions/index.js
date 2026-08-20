const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { initializeApp } = require("firebase-admin/app");

initializeApp();
const db = getFirestore();
const messaging = getMessaging();

exports.remindPendingLegs = onSchedule("every 30 minutes", async () => {
  const now = new Date();
  const twoHoursFromNow = new Date(now.getTime() + 2 * 60 * 60 * 1000);

  const gameWeeksSnap = await db
    .collection("gameWeeks")
    .where("isSettled", "==", false)
    .where("startDate", ">=", now)
    .where("startDate", "<=", twoHoursFromNow)
    .get();

  for (const gwDoc of gameWeeksSnap.docs) {
    const gameWeek = gwDoc.data();

    const [membersSnap, legsSnap] = await Promise.all([
      db.collection("members").where("teamId", "==", gameWeek.teamId).get(),
      db.collection("legs").where("gameWeekId", "==", gwDoc.id).get(),
    ]);

    const submittedMemberIds = new Set(legsSnap.docs.map((d) => d.data().memberId));
    const pendingMembers = membersSnap.docs.filter(
      (m) => !submittedMemberIds.has(m.id)
    );

    for (const memberDoc of pendingMembers) {
      const member = memberDoc.data();
      const userSnap = await db.collection("users").doc(member.userId).get();
      const fcmToken = userSnap.data()?.fcmToken;
      if (!fcmToken) continue;

      await messaging.send({
        token: fcmToken,
        notification: {
          title: "Pick your leg!",
          body: `Gameweek ${gameWeek.weekNumber} kicks off soon — you haven't made your pick yet.`,
        },
        data: {
          type: "leg_reminder",
          gameWeekId: gwDoc.id,
          teamId: gameWeek.teamId,
        },
      });
    }
  }
});

exports.settleLegs = require("./settleLegs").settleLegs;