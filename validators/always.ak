use aiken/transaction.{ScriptContext}

validator {
  fn spend(_datum: Data, _redeemer: Data, _tx: ScriptContext) {
    True
  }
}
