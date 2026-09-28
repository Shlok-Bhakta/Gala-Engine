{
  description = "SwiftTodo iOS development shell";

  inputs.gala.url = "git+ssh://git@github.com/Shlok-Bhakta/Gala-Engine.git";

  outputs = { self, gala }: {
    devShells.x86_64-linux.default = gala.devShells.x86_64-linux.default;
  };
}
