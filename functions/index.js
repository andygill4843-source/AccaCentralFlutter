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
    if (pendingMembers.length === 0) continue;
    const batch = db.batch();
    for (const memberDoc of pendingMembers) {
      const ref = db.collection("notifications").doc();
      batch.set(ref, {
        teamId: gameWeek.teamId,
        recipientMemberId: memberDoc.id,
        type: "deadlineReminder",
        title: "Pick your leg!",
        body: `Gameweek ${gameWeek.weekNumber} kicks off soon — you haven't made your pick yet.`,
        createdAt: new Date(),
        read: false,
      });
    }
    await batch.commit();
  }
});

exports.settleLegs = require("./settleLegs").settleLegs;

exports.deadlineReminder = require('./deadlineReminder').deadlineReminder;

exports.newsPoller = require('./newsPoller').newsPoller;

exports.lineupAnnouncementPoller = require('./lineupAnnouncementPoller').lineupAnnouncementPoller;

exports.runLearningCycle = require('./learningScheduler').runLearningCycle;

exports.getMatchPrediction = require('./getMatchPrediction').getMatchPrediction;

const { onDocumentCreated } = require("firebase-functions/v2/firestore");

exports.sendPushOnNotification = onDocumentCreated("notifications/{notificationId}", async (event) => {
  const data = event.data.data();
  const memberDoc = await db.collection("members").doc(data.recipientMemberId).get();
  if (!memberDoc.exists) return;

  const userSnap = await db.collection("users").doc(memberDoc.data().userId).get();
  const fcmToken = userSnap.data()?.fcmToken;
  if (!fcmToken) return;

  await messaging.send({
    token: fcmToken,
    notification: {
      title: data.title,
      body: data.body,
    },
    data: {
      type: data.type,
      teamId: data.teamId,
    },
  });
});

exports.liveMatchPoller = require('./livePoller').liveMatchPoller;


// ── Dispute vote reminder ─────────────────────────────────────────────────
// Runs daily. Finds disputed fines with exactly ~1 day left and sends a
// reminder to members who haven't voted yet.
exports.remindDisputeVoters = onSchedule('every 24 hours', async () => {
  const now = new Date();
  const in24h = new Date(now.getTime() + 24 * 60 * 60 * 1000);
  const in48h = new Date(now.getTime() + 48 * 60 * 60 * 1000);

  const disputedSnap = await db
    .collection('fines')
    .where('status', '==', 'disputed')
    .get();

  for (const doc of disputedSnap.docs) {
    const fine = doc.data();
    const deadline = fine.disputeDeadline?.toDate();
    if (!deadline) continue;
    // Only act when the deadline falls in the next 24–48 hour window
    // (i.e. approximately 1 day left).
    if (deadline < in24h || deadline > in48h) continue;

    const membersSnap = await db
      .collection('members')
      .where('teamId', '==', fine.teamId)
      .get();

    const votes = fine.votes ?? {};

    for (const memberDoc of membersSnap.docs) {
      const memberId = memberDoc.id;
      // Skip the fined member (can't vote on own fine) and those who already voted.
      if (memberId === fine.memberId) continue;
      if (votes[memberId] !== undefined) continue;

      await db.collection('notifications').add({
        teamId: fine.teamId,
        recipientMemberId: memberId,
        type: 'fineDisputeVote',
        title: '⏰ Last chance to vote ⏰',
        body: `${fine.memberName}'s dispute of the ${fine.fineType} fine closes in less than a day — cast your vote!`,
        read: false,
        createdAt: new Date(),
      });
    }
  }
});