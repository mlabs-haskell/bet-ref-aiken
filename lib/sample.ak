use aiken/collection/list.{filter}

pub fn vericity(l: List<Bool>) -> List<Bool> {
  l
    |> filter(fn(x) { x == True })
}
