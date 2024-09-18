use aiken/crypto.{Blake2b_224, Hash, VerificationKey}
use cardano/assets.{AssetName, PolicyId}

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
    brdBets: List<Pair<PubKeyHash, OracleAnswerDatum>>,
    /// Non-opaque Value
    brdPreviousBet: Pairs<PolicyId, Pairs<AssetName, Int>>,
  }
}

pub type BetRefAction {
  Bet(OracleAnswerDatum)
  Take
}
