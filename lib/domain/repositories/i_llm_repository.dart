abstract class ILLMRepository {
  Future<String> generate(String prompt, {String? system, String? imagePath});
}
