{ inputs, ... }:
{
  flake.nixosModules.bifrost = inputs.bifrost.nixosModules.bifrost;
}
