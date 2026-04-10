Based on dev spec on pc & mobile side [pc side dev spec](../specs/[dev][pc]-3-mobile-folder.md) and [mobile side dev spec](../specs/[dev][mobile]-4-mobile-folder.md), we need to design the pairing flow and the information exchange during pairing.

If needed, refer to other specs (including dev & pm specs) in the `dt_image_search/specs/` folder, e.g. the [service discovery spec](../specs/[dev]%20service%20discovery.md) for device discovery details that are relevant to pairing.

My initial thought: we need to match both side based on information shared via QR payload (e.g. an opt code) to for both side to create a trust relationship (basically a stored device id of the other side) and also create a symmetric key for secure communication. After the initial pairing, we can leverage the trust relationship and the established secure channel to do auto resume of interrupted session without needing to show QR code again, as long as both devices can discover each other (e.g. via USB or LAN, this is planned in Phase 4 though. For now, we can just focus on the initial pairing flow).

We need to design the detailed pairing flow and finalize the information exchange during pairing, and implement the initial pairing flow (make code changes on both pc & ios side, implement other necessary components along the way) in MVP. We can iterate on the design and implementation of the auto resume flow after that.

iOS side code is located in `<repo_root>/mobile/ios/`, and you need to generate a working iOS project in that folder. You can refer to the existing code and structure in that folder, but feel free to make changes as needed to implement the pairing flow elegantly. The pc side code is located in `<repo_root>/dt_image_search/`, and you can also make changes there as needed.

Update existing pm & dev spec if needed and even challenge my instructions if necessary, as long as the final design and implementation are elegant and logical and aligned with the overall product goals and roadmap.

Write down the design in [pairing spec](../specs/[dev]%20pairing.md) and link to relevant specs as needed. Include a sequence diagram to illustrate the flow if needed.

Work on this spec and draft code iteratively, in a `propose, seek feedback, revise` cycle. Don't terminate this chat turn until the design and the draft code are accepted by me.