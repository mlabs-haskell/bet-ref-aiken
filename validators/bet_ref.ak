use aiken/collection/list.{filter, find, push}
use aiken/interval.{
  Finite, Interval, IntervalBound, NegativeInfinity, PositiveInfinity, before,
  contains,
}
use cardano/address.{Address}
use cardano/assets.{Value, merge, negate}
use cardano/transaction.{
  Datum, InlineDatum, Output, OutputReference, Transaction,
}
use types.{
  Bet, BetRefAction, BetRefDatum, BetRefParams, OracleAnswerDatum, POSIXTime,
  Take,
}

validator bet_ref(params: BetRefParams) {
  spend(
    datum: Option<BetRefDatum>,
    brAction: BetRefAction,
    // redeemer
    utxo: OutputReference,
    self: Transaction,
  ) {
    let BetRefParams(oracle_pkh, bet_until, bet_reveal, bet_step) = params
    when brAction is {
      Bet(guess) -> {
        trace @"Previous guess should exist"
        expect Some(previous_guess) = datum
        handle_bet(guess, previous_guess, bet_until, bet_step, utxo, self)
      }
      Take -> handle_take()
    }
  }

  else(_) {
    fail
  }
}

fn handle_bet(
  guess: OracleAnswerDatum,
  input_datum: BetRefDatum,
  bet_until: POSIXTime,
  bet_step: Value,
  utxo: OutputReference,
  self: Transaction,
) -> Bool {
  expect Some(own_input) =
    self.inputs |> find(fn(i) { i.output_reference == utxo })
  trace @"Expected only one continuing output"
  expect [s_out] = get_continuing_outputs(own_input.output.address, self)

  let out_value = s_out.value
  let in_value = own_input.output.value
  expect InlineDatum(data) = s_out.datum
  expect BetRefDatum(guesses, bet_value) = data
  let BetRefDatum(prev_guesses, prev_bet_value) = input_datum

  trace @"Must be before `BetUntil` time"
  let to_bet_until: Interval<POSIXTime> = before(bet_until)
  expect to_bet_until |> interval_contains(self.validity_range)

  trace @"New guesses should be updated correctly"
  expect [signer_pkh] = self.extra_signatories
  expect ( prev_guesses |> push(Pair(signer_pkh, guess)) ) == guesses

  trace @"The current bet must be more than the previous bet by at least `bet_step` amount"
  //FIXME: this is not very clear to me
  let min_out_value = in_value |> merge(prev_bet_value) |> merge(bet_step)
  expect out_value |> value_geq(min_out_value)

  trace @"Out bet value is wrong"
  let expected_in_value = out_value |> merge(negate(bet_value))
  expect in_value == expected_in_value

  // We are done
  True
}

fn handle_take() -> Bool {
  fail
  //     Take ->
  //       let
  //         -- Note that `find` returns the first match. Since we were always prepending, this is valid.
  //         Just guess = find ((== signerPkh) . fst) previousGuesses
  //         oracleIn = case filter (isNothing . txOutReferenceScript) (txInInfoResolved <$> txInfoReferenceInputs info) of
  //           [oracleIn'] -> oracleIn'
  //           [] -> traceError "No reference input provided"
  //           _anyOtherMatch -> traceError "Expected only one reference input"
  //         oracleAnswer = case outputToDatum oracleIn of
  //           Nothing -> traceError "Could not resolve for datum"
  //           (Just (OracleAnswerDatum oracleAnswer')) -> oracleAnswer'
  //         guessDiff = getGuessDiff $ snd guess
  //         getGuessDiff (OracleAnswerDatum g) = abs (oracleAnswer - g)
  //         -- Unwrapping the 'Maybe' here to extract the 'Just' (and trace error for 'Nothing') kills PlutusTx compilation
  //         -- the issue is that GHC will fire the worker wrapper transformation combining this with the equality with 'oraclePkh'
  //         -- code down below. Which will cause issues with BuiltinByteString also being unwrapped into primitive pointers.
  //         -- See: https://github.com/IntersectMBO/plutus/issues/4193
  //         mOracleInPkh = toPubKeyHash (txOutAddress oracleIn)
  //        in
  //         traceIfFalse
  //           "Must be after `RevealTime`"
  //           (from betReveal `contains` validRange)
  //           && traceIfFalse
  //             "Must fully spend Script"
  //             (null (getContinuingOutputs ctx))
  //           && traceIfFalse
  //             "Reference input must be from Oracle address (wrt Payment part)"
  //             (mOracleInPkh == Just oraclePkh)
  //           && traceIfFalse
  //             "Guess is not closest"
  //             (all (\pg -> getGuessDiff (snd pg) >= guessDiff) previousGuesses)
}

//   outputToDatum :: FromData b => TxOut -> Maybe b
//   outputToDatum o = case txOutDatum o of
//     NoOutputDatum -> Nothing
//     OutputDatum d -> processDatum d
//     OutputDatumHash dh -> processDatum =<< findDatum dh info
//    where
//     processDatum = fromBuiltinData . getDatum

// Helpers

// Get all the outputs that pay to the same script address we are currently \
// spending from, if any.
fn get_continuing_outputs(own_addr: Address, tx: Transaction) -> List<Output> {
  tx.outputs |> filter(fn(o) { o.address == own_addr })
}

fn interval_contains(container: Interval<Int>, containee: Interval<Int>) -> Bool {
  let Interval(er_lower_bound, er_upper_bound) = container
  let Interval(ee_lower_bound, ee_upper_bound) = containee
  let IntervalBound(er_lower_bound_type, er_lower_bound_is_inclusive) =
    er_lower_bound
  let IntervalBound(ee_lower_bound_type, _is_inclusive) = ee_lower_bound
  let IntervalBound(er_upper_bound_type, er_upper_bound_is_inclusive) =
    er_upper_bound
  let IntervalBound(ee_upper_bound_type, _is_inclusive) = er_upper_bound
  // Lower bound
  let lower_check =
    when (er_lower_bound_type, ee_lower_bound_type) is {
      (NegativeInfinity, _) -> True
      (Finite(a), Finite(b)) ->
        if er_lower_bound_is_inclusive {
          a <= b
        } else {
          a < b
        }
      (PositiveInfinity, _) -> False
      _ -> False
    }
  // Should never happen
  // Upper bound
  let upper_check =
    when (er_upper_bound_type, ee_upper_bound_type) is {
      (NegativeInfinity, _) -> False
      (Finite(a), Finite(b)) ->
        if er_upper_bound_is_inclusive {
          a >= b
        } else {
          a > b
        }
      (PositiveInfinity, _) -> True
      _ -> False
    }

  // Should never happen
  //
  lower_check && upper_check
}

fn value_geq(a: Value, b: Value) -> Bool {
  todo
}
