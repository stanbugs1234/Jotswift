// Erases everything an account owns when the account is deleted. Apple
// requires apps with accounts to delete the account's data with it.

import type { Firestore } from "firebase-admin/firestore";

/** Deletes every Storage file whose name starts with a prefix. */
export type DeleteFiles = (prefix: string) => Promise<void>;

/** Deletes users/{uid} with all its subcollections (notebooks, pages, ink,
 * tasks, events...) and the account's files (cover photos). */
export async function eraseUser(
  db: Firestore,
  deleteFiles: DeleteFiles,
  uid: string,
): Promise<void> {
  if (!uid || uid.includes("/")) throw new Error(`Bad uid: ${uid}`);
  await Promise.all([
    db.recursiveDelete(db.doc(`users/${uid}`)),
    deleteFiles(`users/${uid}/`),
  ]);
}
