# Model-selection categories owned by the `models` package. Consumers may attach
# their own runtime bindings, but application-independent targets stay here.
{
  pi = {
    target = "pi";
    label = "Pi";
    description = "Bare Pi's single default model selection";
    # Keep the default present in the reviewed catalog so first-run Pi generation
    # never produces a setting that Pi cannot resolve.
    defaultModel = "router/gpt-5.6-terra";
  };
}
