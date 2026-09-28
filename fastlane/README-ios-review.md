# iOS review replacement

`ios submit` uploads the configured build if absent and waits for that exact iOS
marketing version/build to become `VALID`, including on retries. Jolene's export
declaration must be `usesNonExemptEncryption: false`; true or unknown requires a
separate compliance check. A failed, invalid, expired, ambiguous or timed-out build
never causes review cancellation.

The guard only cancels an observed `WAITING_FOR_REVIEW` version with exactly one
matching review submission containing exactly one matching App Store version
item. It reads every page of the version, build, submission and item collections.
It rechecks the new build and old review immediately before the cancellation.
`IN_REVIEW`, pending release, unknown states and submissions with other items
stop automatically. The distributed version is never changed by the guard.

Cancellation uses `PATCH /v1/reviewSubmissions/{id}` with `canceled: true`.
The guard waits for `DEVELOPER_REJECTED` and no active cancellation before allowing
deliver to select and submit the new build with automatic release. It never uses
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

Run offline checks with `ruby fastlane/ios_review_submission.test.rb`. They require
no Fastlane installation, credentials or network. The lane itself uses the pinned
Fastlane 2.240.1 API.

Sources checked:

- [Apple: remove a submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/remove-a-submission-from-review)
- [Apple: modify a review submission](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-reviewsubmissions-_id_)
- [Fastlane 2.240.1 runner](https://github.com/fastlane/fastlane/blob/2.240.1/deliver/lib/deliver/runner.rb)
- [Fastlane 2.240.1 app and review selection](https://github.com/fastlane/fastlane/blob/2.240.1/spaceship/lib/spaceship/connect_api/models/app.rb)
- [Fastlane 2.240.1 build states](https://github.com/fastlane/fastlane/blob/2.240.1/spaceship/lib/spaceship/connect_api/models/build.rb)
