Based on pm spec [mobile-folder pm spec for mobile](../specs/%5Bpm%5D%20%5Bmobile%5D%202.%20mobile-folder.md) and UI mock files in folder `<repo_root>/dt_image_search/prompt/ui-mobile-folder` and feature roadmap in [feature roadmap](../specs/feature%20roadmap%20-%20mobile-folder.md), generate a detailed dev design spec for mobile side. This version of the dev spec should focus on the MVP phase but should also accommodate future extensibility for later phases.

Refer to pc side pm specs for context: [image search pm spec for pc](../specs/%5Bpm%5D%20%5Bpc%5D%200.%20image-search.md) and [mobile-folder pm spec for pc](../specs/%5Bpm%5D%20%5Bpc%5D%201.%20mobile-folder.md) .

Each roadmap phase should be in a seperate section, and for now later phases than the MVP can be left with high level descriptions without going into detailed design. The MVP phase should have detailed actionable design covering all the features planned for the MVP.

Put the dev spec in the file [dev spec](../specs/%5Bdev%5D%5Bmobile%5D-4-mobile-folder.md).
Put the minimum initial code implementation in the `<repo_root>/mobile/ios`. For now, we only focus on iOS platform.

Work on this dev spec in an iterative manner:
1. Propose a dev spec draft along with minimum initial code implementation and save them in the specified locations.
2. Ask me for feedbacks.
3. Go back to step 1 with feedbacks incorporated until the draft is accepted explicitly by me.

Early iterations can be high level and focus on covering core features, while later iterations can go into more and more details, covering specific implementation approaches, relevant code paths, and any necessary changes to existing code. The initial code implementation should be minimum and only need to be helpful for illustrating the design and getting feedback, it doesn't need to be fully functional or cover all edge cases at the early stages. The goal of this process is to ensure that the design is well thought out, covers all necessary aspects, and has buy-in before any development work begins.

I have written the initial draft of the dev spec covering only the fundamental engineering choices. Please rewrite the spec respecting the core engineering choices I made but feel free to reorganize the structure, rephrase the content, and add more details as you see fit.

Don't terminate this chat turn until the dev spec and the initial code implementation is accepted explicitly by me.