namespace Logic {
    /*
     * Container engines ComposeDeck can talk to. Both expose a
     * Docker-compatible API over a Unix socket, so requests are shared;
     * only service activation and compose invocation differ.
     */
    public enum ContainerEngine {
        NONE,
        PODMAN,
        DOCKER
    }
}
