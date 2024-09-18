use aiken/crypto.{Blake2b_224, Hash, VerificationKey}
use cardano/assets.{Value}

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
    brpBetStep: Value,
  }
}

pub type PubKeyHash =
  Hash<Blake2b_224, VerificationKey>

pub type POSIXTime =
  Int

pub type BetRefDatum {
  BetRefDatum {
    brdBets: List<Pair<PubKeyHash, OracleAnswerDatum>>,
    brdPreviousBet: Value,
  }
}

pub type BetRefAction {
  Bet(OracleAnswerDatum)
  Take
}
