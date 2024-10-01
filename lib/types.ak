use aiken/cbor.{diagnostic}
use aiken/hash.{Blake2b_224, Hash}
use aiken/transaction/credential.{VerificationKey}
use aiken/transaction/value.{AssetName, PolicyId}

pub type TeamGoals =
  Int

pub type OracleAnswerDatum {
  OracleAnswerDatum(TeamGoals)
}

pub type BetRefParams {
  BetRefParams {
    brpOraclePkh: PubKeyHash,
    brpBetUntil: POSIXTime,
    brpBetReveal: POSIXTime,
    /// Non-opaque Value
    brpBetStep: Pairs<PolicyId, Pairs<AssetName, Int>>,
  }
}

pub type PubKeyHash =
  Hash<Blake2b_224, VerificationKey>

pub type POSIXTime =
  Int

pub type BetRefDatum {
  BetRefDatum {
    brdBets: List<BBet>,
    /// Non-opaque Value
    brdPreviousBet: Pairs<PolicyId, Pairs<AssetName, Int>>,
  }
}

pub type BBetRefDatum {
  BBetRefDatum {
    brdBets: List<BBet>,
    /// Non-opaque Value
    brdPreviousBet: Pairs<PolicyId, Pairs<AssetName, Int>>,
  }
}

pub type BBet {
  BBet(PubKeyHash, OracleAnswerDatum)
}

pub type BetRefAction {
  Bet(OracleAnswerDatum)
  Take
}

test foo() {
  let d = BetRefDatum([BBet("", OracleAnswerDatum(42))], [])
  diagnostic(d) == @"121([_ [_ 121([_ h'', 121([_ 42])])], {}])"
}
