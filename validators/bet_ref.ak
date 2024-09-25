use aiken/dict.{Dict, foldl, map, union_with, values}
use aiken/interval.{
  Finite, Interval, IntervalBound, NegativeInfinity, PositiveInfinity, after,
  before,
}
use aiken/list.{all, concat, filter, find, push}
use aiken/math.{abs}
use aiken/transaction.{
  InlineDatum, Output, OutputReference, ScriptContext, Spend, Transaction,
  find_input,
}
use aiken/transaction/credential.{Address, VerificationKeyCredential}
use aiken/transaction/value.{
  AssetName, PolicyId, Value, from_asset_list, merge, negate, to_dict,
}
use types.{
  Bet, BetRefAction, BetRefDatum, BetRefParams, OracleAnswerDatum, POSIXTime,
  PubKeyHash, Take,
}

// use aiken/collection/dict.{Dict, foldl, map, union_with, values}
// use aiken/collection/list.{all, concat, filter, find, push}
// use aiken/interval.{
//   Finite, Interval, IntervalBound, NegativeInfinity, PositiveInfinity, after,
//   before,
// }
// use aiken/math.{abs}
// use cardano/address.{Address, VerificationKey}
// use cardano/assets.{
//   AssetName, PolicyId, Value, from_asset_list, merge, negate, to_dict,
// }
// use cardano/transaction.{InlineDatum, Output, OutputReference, Transaction}
// use types.{
//   Bet, BetRefAction, BetRefDatum, BetRefParams, OracleAnswerDatum, POSIXTime,
//   PubKeyHash, Take,
// }

validator(params: BetRefParams) {
  fn spend(datum: BetRefDatum, brAction: BetRefAction, self: ScriptContext) {
    let BetRefParams(oracle_pkh, bet_until, bet_reveal, bet_step_list) = params
    let bet_step = from_asset_list(bet_step_list)
    // own input
    expect Spend(ref) = self.purpose
    expect Some(own) = self.transaction.inputs |> find_input(ref)
    when brAction is {
      Bet(guess) -> {
        trace @"Previous guess should exist"
        handle_bet(
          guess,
          datum,
          bet_until,
          bet_step,
          own.output_reference,
          self.transaction,
        )
      }
      Take ->
        handle_take(
          datum,
          oracle_pkh,
          bet_reveal,
          own.output_reference,
          self.transaction,
        )
    }
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
  expect BetRefDatum(guesses, bet_value): BetRefDatum = data
  let BetRefDatum(prev_guesses, prev_bet_value) = input_datum

  trace @"Must be before `BetUntil` time"
  let to_bet_until: Interval<POSIXTime> = before(bet_until)
  expect to_bet_until |> interval_contains(self.validity_range)

  trace @"New guesses should be updated correctly"
  expect [signer_pkh] = self.extra_signatories
  expect ( prev_guesses |> push(Pair(signer_pkh, guess)) ) == guesses

  trace @"The current bet must be more than the previous bet by at least `bet_step` amount"
  //FIXME: this is not very clear to me
  let min_out_value =
    in_value |> merge(from_asset_list(prev_bet_value)) |> merge(bet_step)
  expect out_value |> geq(min_out_value)

  trace @"Out bet value is wrong"
  let expected_in_value = out_value |> merge(negate(from_asset_list(bet_value)))
  expect in_value == expected_in_value

  // We are done
  True
}

fn handle_take(
  datum: BetRefDatum,
  oracle_pkh: PubKeyHash,
  bet_reveal: POSIXTime,
  utxo: OutputReference,
  self: Transaction,
) -> Bool {
  trace @"Expected only one signature"
  expect [signer_pkh] = self.extra_signatories
  let BetRefDatum(brdBets, ..) = datum

  trace @"Bet must ne on the list"
  expect Some(bet) = brdBets |> find(fn(e) { e.1st == signer_pkh })

  trace @"Expected only one reference input"
  expect [oracleIn] = self.reference_inputs

  trace @"Oracle datum is expected"
  expect InlineDatum(oracle_datum_) = oracleIn.output.datum
  expect oracle_datum: OracleAnswerDatum = oracle_datum_
  let OracleAnswerDatum(oracle_answer) = oracle_datum

  let get_guess_diff =
    fn(d: OracleAnswerDatum) -> Int {
      let OracleAnswerDatum(teamGoal) = d
      abs(oracle_answer - teamGoal)
    }

  let guess_diff = get_guess_diff(bet.2nd)

  trace @"Oracle PKH is correct"
  let Address(payment_credential, ..) = oracleIn.output.address
  expect VerificationKeyCredential(actual_oracle_pub_key_hash) =
    payment_credential
  expect actual_oracle_pub_key_hash == oracle_pkh

  trace @"Must be after `RevealTime`"
  let from_reveal_after: Interval<POSIXTime> = after(bet_reveal)
  expect from_reveal_after |> interval_contains(self.validity_range)

  trace @"Must be fuly spent"
  expect Some(own_input) =
    self.inputs |> find(fn(i) { i.output_reference == utxo })
  expect [] = get_continuing_outputs(own_input.output.address, self)

  trace @"Guess must be the closest one"

  expect brdBets |> all(fn(b) { get_guess_diff(b.2nd) >= guess_diff })

  // We are done
  True
}

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
