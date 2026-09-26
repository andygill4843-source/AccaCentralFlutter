const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getFirestore } = require('firebase-admin/firestore');

const db = getFirestore();

exports.deadlineReminder = onSchedule(
  { schedule: 'every day 09:00', timeZone: 'Europe/London', timeoutSeconds: 120, memory: '256MiB' },
  async () => {
    const now = Date.now();
    const gameWeeksSnap = await db.collection('gameWeeks')
      .where('isLocked', '==', false)
      .where('isSettled', '==', false)
      .get();

    for (const doc of gameWeeksSnap.docs) {
      const gw = doc.data();
      if (gw.deadlineReminderSent) continue;
      const hoursUntil = (gw.deadline.toMillis() - now) / (1000 * 60 * 60);
      if (hoursUntil < 20 || hoursUntil > 28) continue;

      const teamId = gw.teamId;
      const membersSnap = await db.collection('members').where('teamId', '==', teamId).get();
      const allMemberIds = membersSnap.docs.map(d => d.id);

      const legsSnap = await db.collection('legs')
        .where('gameWeekId', '==', doc.id)
        .where('isSecondaryTournamentLeg', '==', false)
        .get();
      const submittedMemberIds = new Set(legsSnap.docs.map(d => d.data().memberId));
      const outstandingCount = allMemberIds.filter(id => !submittedMemberIds.has(id)).length;

      const body = outstandingCount > 0
        ? `⚠️⚠️ One day until gameweek ${gw.weekNumber} deadline. ${submittedMemberIds.size}/${allMemberIds.length} legs are in. Is it the usual culprits outstanding? 👀`
        : `⚠️⚠️ One day until gameweek ${gw.weekNumber} deadline and we're set. All selections for the week are in and it's over to the backroom staff to work their magic 🫡.`;

      for (const memberId of allMemberIds) {
        await db.collection('notifications').add({
          teamId,
          recipientMemberId: memberId,
          type: 'deadlineReminder',
          title: '⏰ Deadline approaching',
          body,
          read: false,
          createdAt: new Date(),
        });
      }

      await doc.ref.update({ deadlineReminderSent: true });
    }
  }
);