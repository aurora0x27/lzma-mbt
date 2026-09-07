///|
test "error_constructors" {
  ignore(InvalidInput("x"))
  ignore(UnexpectedEof)
  ignore(InvalidConfiguration("x"))
  ignore(UnsupportedFeature("x"))
  ignore(MemoryLimit)
  ignore(DataError)
  ignore(BufferTooSmall)
  ignore(FormatError)
}
