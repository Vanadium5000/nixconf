{ self }:
{
  config = {
    custom-antigravity = {
      npm = "@ai-sdk/openai-compatible";
      name = "Antigravity";
      options = {
        baseURL = "http://127.0.0.1:8045/v1";
        api_key = self.secrets.ANTIGRAVITY_MANAGER_KEY;
      };
    };
  };
}
