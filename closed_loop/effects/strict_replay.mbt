///|
/// Package-private neutral state derived only from strict committed event bytes.
/// It does not claim governance authorization; it is the retry provenance view.
priv struct StrictRetrySnapshot {
  workflow : @contracts.RecordRef
  policy_ref : @contracts.RecordRef
  sequence : Int64
  revision : Int64
  last_event_digest : @contracts.ContentDigest?
  replay_digest : @contracts.ContentDigest
  attempts : ReadOnlyArray[DecodedAttemptRecord]
  intents : ReadOnlyArray[DecodedIntentRecord]
  observations : ReadOnlyArray[DecodedObservationRecord]
  receipts : ReadOnlyArray[DecodedReceiptRecord]
  receipt_event_refs : ReadOnlyArray[@contracts.RecordRef]
  requests : ReadOnlyArray[DecodedReconciliationRequestRecord]
  request_event_refs : ReadOnlyArray[@contracts.RecordRef]
  reconciliations : ReadOnlyArray[DecodedReconciliationRecord]
  reconciliation_event_refs : ReadOnlyArray[@contracts.RecordRef]
  consumed_event_refs : ReadOnlyArray[@contracts.RecordRef]
  matched_outbox_refs : ReadOnlyArray[@contracts.RecordRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}
