# iOS review replacement

Since lot 6, the guard is used by `ios submit_native` (Swift app, workflow
`.github/workflows/ios-native-app-store.yml`, `docs/mobile-swift/APP_STORE.md`).
The former `ios submit` lane of the Capacitor shell is retired and only raises
an explicit error.

`ios submit_native` never uploads a binary: the build must already be on
TestFlight. If it is absent, the lane stops; otherwise it waits for that exact iOS
marketing version/build to become `VALID`, including on retries. It refuses to run
outside the `soumettre` job of that workflow on `main`, without the verdict of the
guards of the same run attempt, or without the exact confirmation phrase
(`IosReviewSubmission.exiger_contexte_workflow!`). It submits with a phased release
over seven days; release after approval is automatic or manual, as chosen when the
workflow is dispatched. Jolene's export declaration must be
`usesNonExemptEncryption: false`; true or unknown requires a separate compliance
check. A failed, invalid, expired, ambiguous or timed-out build never causes
review cancellation.

The guard only cancels an observed `WAITING_FOR_REVIEW` version with exactly one
matching review submission containing exactly one matching App Store version
item. It reads every page of the version, build, submission and item collections.
It rechecks the new build and old review immediately before the cancellation.
`IN_REVIEW`, pending release, unknown states and submissions with other items
stop automatically. The distributed version is never changed by the guard.

Cancellation uses `PATCH /v1/reviewSubmissions/{id}` with `canceled: true`.
The guard waits for `DEVELOPER_REJECTED` and no active cancellation before allowing
deliver to select and submit the new build (phased, automatic or manual release). It never uses
the deprecated appStoreVersionSubmissions deletion API or deliver's implicit
`reject_if_possible` behavior. No mutation is retried automatically after an error.

Apple does not expose an atomic state precondition on this cancellation request.
A server transition from `WAITING_FOR_REVIEW` to `IN_REVIEW` between the last read
and PATCH is therefore still possible. The guard refuses any `IN_REVIEW` state it
observes; it cannot guarantee that no transition occurs between requests.

Processing and cancellation polling each stop after 30 minutes by default.
Re-running after a processing error waits again without re-uploading an existing
build. Re-running during `CANCELING` waits without sending another cancellation;
after `DEVELOPER_REJECTED`, it can continue. An exact build already submitted or
distributed is a no-op, except `PENDING_DEVELOPER_RELEASE`, which reports that a
separate release action is needed. A populated draft is preserved and reported;
an empty draft can be reused by deliver. Local metadata/API errors after successful
cancellation can still leave the old version developer-rejected; re-run only after
resolving the reported error.

Review notes (`fastlane/ios_review_notes.rb`, `fastlane/ios_review_demo_account.rb`,
`IosReviewSubmission.enchainer!`): before this guard runs, a pre-flight that writes nothing to
Apple checks the editable version that deliver will use (`App#get_edit_app_store_version`).
It must be the configured marketing version (another editable version, which deliver's
`ensure_version!` would rename, stops the lane). The review detail that will be submitted
(after the planned copy, if any) must carry demo credentials. They are signed in to
production Supabase exactly like the native app (password grant, publishable `apikey`, no
captcha), the role is read with `fn_get_my_role` (soignant or établissement only), and that
session is revoked at once (`logout?scope=local`). The verified role picks the block,
`config/ios-review-notes-2.0-soignant.txt` or `-etablissement.txt`. The same pre-flight alone
runs in the `gardes` job, in both modes (`fastlane ios preflight_review_native`).

After this guard, the version is found or created (same request as `ensure_version!`). Only
if it has no demo credentials, the review detail of the single distributed version is
copied API to API: credentials as a whole with `demoAccountRequired` set to true, then
contacts and notes only where the target is empty; credentials already present are never
overwritten. An unknown (`null`) `demoAccountRequired` next to present credentials is written
true. The submitted detail must carry the credentials signed in at pre-flight. Then the
`notes` attribute is patched: the block, the separator line
`--- Notes from version 1.0.7 (previous hybrid app) ---`, then the previous notes, within
3,900 UTF-16 units. The lane never passes `app_review_information` to deliver, which would
reset `demoAccountRequired`. No review detail value is ever printed. Spaceship still logs
request and response bodies to `$TMPDIR/spaceship*.log`: never run with `VERBOSE` or
`--verbose`, never upload the temporary directory; the workflow deletes these logs. deliver
deletes the review attachments of the detail on every submission (existing 2.240.1
behaviour). Details: `docs/mobile-swift/APP_STORE.md`.

Run offline checks with `ruby fastlane/ios_review_submission.test.rb` and
`ruby fastlane/ios_review_notes.test.rb`. They require no Fastlane installation,
credentials or network. The lane itself uses the pinned Fastlane 2.240.1 API.

Sources checked:

- [Apple: remove a submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/remove-a-submission-from-review)
- [Apple: modify a review submission](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-reviewsubmissions-_id_)
- [Fastlane 2.240.1 runner](https://github.com/fastlane/fastlane/blob/2.240.1/deliver/lib/deliver/runner.rb)
- [Fastlane 2.240.1 app and review selection](https://github.com/fastlane/fastlane/blob/2.240.1/spaceship/lib/spaceship/connect_api/models/app.rb)
- [Fastlane 2.240.1 build states](https://github.com/fastlane/fastlane/blob/2.240.1/spaceship/lib/spaceship/connect_api/models/build.rb)
