; A live stream has no total-duration deadline. Only stalled transfers expire.
class HttpStreamTimeouts {
    static IdleSeconds() {
        seconds := 120
        if EnvGet("AHKLLM_E2E_WORKER") != "" && EnvGet("AHKLLM_E2E_DATA_DIR") != "" {
            override := EnvGet("AHKLLM_E2E_STREAM_IDLE_SECONDS")
            if RegExMatch(override, "^\d+$") && Integer(override) >= 1 && Integer(override) <= 120
                seconds := Integer(override)
        }
        return seconds
    }
    static Options() => "--speed-limit 1 --speed-time " this.IdleSeconds()
}
