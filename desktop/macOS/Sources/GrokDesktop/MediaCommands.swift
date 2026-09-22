import Foundation

/// Mirrors xai-grok-tools-api/src/slash_commands.rs, including the pager's tool gates.
enum MediaCommand {
    static func requiredTool(_ name: String) -> String? {
        switch name {
        case "imagine": return "image_gen"
        case "imagine-video": return "image_to_video"
        default: return nil
        }
    }

    static func instruction(video: Bool, description: String) -> String {
        if video { return videoInstruction + "\n\nUser prompt: " + description }
        return "Call the image_gen tool immediately, passing the user's prompt below verbatim — do not rewrite, embellish, or expand it. After the tool completes, briefly acknowledge and mention where the image was saved.\n\nPrompt: " + description
    }

    private static let videoInstruction = """
# Imagine Video

Video starts from an image — there is no text-to-video tool. Default to `image_to_video`; use `reference_to_video` when the user explicitly asks for it, a shot genuinely needs multiple reference images, or the subject should speak in a specific preset voice (`voices`).

If a video tool fails with a zero-data-retention (ZDR) storage error, relay that error verbatim and stop the workflow — do not generate more source images or retry.

## Default: single clip

Unless the user asks for a long video, multiple scenes, or a multi-shot sequence, generate **one** video:

1. Create a source image with `image_gen` that stages the first frame (composition, subject, lighting).
2. Call `image_to_video` with that image and a short prompt describing the motion or camera move (1–2 sentences, present tense).
3. After the tool completes, mention the saved file path so the user can find it.

## Longer / multi-shot videos

When the user requests a longer video, multiple scenes, or a narrative sequence:

1. **Plan the story as shots** — break the idea into distinct shots, one beat each.
2. **Favor frequent, short shots** — prefer more 6s clips over fewer long ones; more cuts keep it dynamic.
3. **Create each shot's source image** with `image_gen` (or `image_edit` to combine references), keeping characters and settings consistent across shots.
4. **Animate each shot with `image_to_video`** — the source image becomes frame 1.
5. **Assemble with FFmpeg** using stream copy (`ffmpeg -f concat ... -c copy` — never re-encode). Keep every shot at the same resolution and frame rate so the concat works. After assembly, mention the final output path.

## Shot guidance

- **Prompt-craft:** one short, vivid moment in present tense with a clear camera movement, in 1–2 sentences.
- **Minimal but interesting:** one clear subject, one simple motion or camera move per shot. Avoid complex multi-action animation; make the shot compelling through composition, lighting, and a strong moment.
- **Complex source image?** Intricate frames (busy geometry, fine detail, heavy reflections) warp when animated. Keep the subject fixed and move only the camera (slow push-in, orbit, or parallax), or break into simpler shots. For new shots, generate a simpler, animation-friendly base image rather than animating a busy one.
- **`image_to_video` animates from frame 1** — stage the first frame with `image_gen`/`image_edit` before animating.
- **Aspect ratio:** set it on the source image (`image_gen` `aspect_ratio`); don't re-crop an existing video.
- **Duration:** 6s or 10s only (prefer 6s); round to the nearest. `reference_to_video` accepts 1–15s.
- **Speaking subjects:** to give a subject a voice, use `reference_to_video` with `voices` (up to 3 preset voice identifiers, e.g. "ara", "eve") and tag them in the prompt as `<AUDIO_0>`…; combine with reference `images` tagged `<IMAGE_0>`… for a consistent character.
- **Real people:** reference-first — drive the video from a verified reference image; never animate a named person without one.
- Don't loop the same clip unless asked.
"""
}

extension AppStore {
    func generateMedia(kind: String, description: String) {
        guard ["image", "video", "imagine", "imagine-video"].contains(kind) else { return }
        let video = kind == "video" || kind == "imagine-video"
        let command = video ? "imagine-video" : "imagine"
        let tool = video ? "image_to_video" : "image_gen"
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { banner = "Usage: /\(command) <description>"; return }
        guard !run.isRunning, !run.isConfiguring else { banner = "Wait for the current turn to finish or stop it before generating media."; return }
        if let tools = run.availableTools, !tools.contains(tool) {
            banner = "This runtime does not provide the \(tool) tool."; return
        }
        let priorDraft = draft
        let priorProjectID = state.selectedProjectID
        send(displayText: "/\(command) \(description)", promptText: MediaCommand.instruction(video: video, description: description), requiredTool: tool)
        if !priorDraft.isEmpty, SlashCommand.split(priorDraft) == nil, state.selectedProjectID == priorProjectID, draft.isEmpty { draft = priorDraft }
    }
}
