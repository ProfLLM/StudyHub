/// Optional capability for generating a complete Class without existing notes.
abstract interface class ClassGenerationProvider {
  Future<String> generateClass({required String request});
}
