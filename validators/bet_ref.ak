use aiken/collection/dict.{Dict, foldl, map, union_with, values}
use aiken/collection/list.{all, concat, filter, find, push}
use aiken/interval.{
  Finite, Interval, IntervalBound, NegativeInfinity, PositiveInfinity, before,
}
use cardano/address.{Address}
use cardano/assets.{AssetName, PolicyId, Value, merge, negate, to_dict}
use cardano/transaction.{InlineDatum, Output, OutputReference, Transaction}
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
    let BetRefParams(_oracle_pkh, bet_until, _bet_reveal, bet_step) = params
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
  expect out_value |> geq(min_out_value)

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
  let IntervalBound(ee_upper_bound_type, _is_inclusive) = ee_upper_bound
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

// Some partial order operations over Value

type These<a, b> {
  This(a)
  That(b)
  These(a, b)
}

fn combine(l: These<a, b>, r: These<a, b>) -> These<a, b> {
  when (l, r) is {
    (This(a), That(b)) -> These(a, b)
    (That(b), This(a)) -> These(a, b)
    _ -> fail
  }
}

fn check_bin_rel(f: fn(Int, Int) -> Bool, l: Value, r: Value) {
  let un_these =
    fn(these: These<Int, Int>) -> Bool {
      when these is {
        This(a) -> f(a, 0)
        That(b) -> f(0, b)
        These(a, b) -> f(a, b)
      }
    }
  check_pred(un_these, l, r)
}

fn check_pred(pred: fn(These<Int, Int>) -> Bool, l: Value, r: Value) -> Bool {
  // Helper function to map values into combinable format
  let mk_these =
    fn(con: fn(Int) -> These<Int, Int>) -> fn(ByteArray, Dict<AssetName, Int>) ->
      Dict<AssetName, These<Int, Int>> {
      fn(_, d) { d |> map(fn(_, i) { con(i) }) }
    }
  // Map over dictiorinized values
  let ld: Dict<PolicyId, Dict<AssetName, These<Int, Int>>> =
    l |> to_dict |> map(mk_these(This))
  let rd: Dict<PolicyId, Dict<AssetName, These<Int, Int>>> =
    r |> to_dict |> map(mk_these(That))

  // Build union
  let u: Dict<PolicyId, Dict<AssetName, These<Int, Int>>> =
    union_with(
      ld,
      rd,
      fn(_, li, ri) {
        Some(
          union_with(li, ri, fn(_, this, that) { Some(combine(this, that)) }),
        )
      },
    )
  // Make a list of all values
  let l: List<These<Int, Int>> =
    u |> foldl([], fn(_, inner, res) { res |> concat(values(inner)) })

  // Check the predicate
  l |> all(pred)
}

fn geq(a: Value, b: Value) -> Bool {
  check_bin_rel(>=, a, b)
}
