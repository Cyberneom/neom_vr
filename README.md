#neom_vr
neom_vr is an experimental module within the Open Neom ecosystem, dedicated to researching
and developing Virtual Reality (VR) functionalities specifically tailored for smartphone VR users.
Our core philosophy is that VR must be democratized and made accessible to everyone,
not just those with expensive high-end equipment. This module explores novel ways to deliver
immersive experiences using readily available mobile devices.

This module serves as a sandbox for R&D in mobile VR, investigating how to integrate immersive
content (360 videos, panoramas) and potentially biofeedback data within a smartphone-centric VR environment.
It aims to push the boundaries of what's possible with accessible VR, aligning with the Tecnozenism vision
of harmonizing technology with conscious experience for all. neom_vr adheres to Open Neom's Clean Architecture
principles where possible, ensuring its experimental nature doesn't compromise the overall project's integrity.
It integrates with neom_core for core services and neom_commons for shared UI components,
providing a foundation for future, more robust VR features.

🌟 Features & Responsibilities
In its current version (v1.0.0), neom_vr experimentally offers:
•	360 Video Playback: Provides functionalities for playing immersive 360-degree videos
    (Neom360ViewerPage, VideoSection), allowing users to look around the virtual environment by moving their phone.
•	Panoramic Image Viewer: Enables viewing of 360-degree panoramic images (PanoramaView), offering a static immersive experience.
•	Smartphone VR Split View: Utilizes split_view to create a side-by-side display, mimicking the stereoscopic view
    required for VR headsets (like Google Cardboard or similar smartphone VR viewers).
•	External VR Browser Integration: Includes experimental functionality (NeomChromePage) to launch external
    web-based VR experiences (e.g., WebVR/WebXR demos) in a custom tab or browser.
•	Playback Controls: Offers basic playback controls for 360 videos (play, stop, reset, seek).
•	Experimental R&D: Serves as a testbed for integrating various VR libraries and exploring their capabilities on mobile.

Future Expansion (Roadmap)
As an experimental module, neom_vr has an ambitious long-term roadmap that aims to achieve functionalities similar 
to advanced VR platforms, but optimized for smartphones:
•	Enhanced 360/VR Content Integration: Seamless integration of VR content into the main Open Neom timeline and user profiles.
•	Interactive VR Experiences: Development of simple interactive VR scenes and guided meditations within the app.
•	Biofeedback Visualization in VR: Displaying real-time biofeedback data (e.g., from EEG wearables)
    as visual elements within the VR environment.
•	Spatial Audio Integration: Implementing immersive 3D audio to enhance VR experiences.
•	VR Navigation & UI: Designing intuitive VR-specific navigation and user interfaces for smartphone users.
•	Custom VR Environments: Allowing users to create or customize their own VR spaces for meditation or focus.
•	Multiplayer VR (Basic): Exploring basic shared VR experiences for guided group meditations or collaborative research.
•	Performance Optimization: Continuous research into optimizing VR rendering and processing for low-power mobile devices.

🛠 Technical Highlights / Why it Matters (for developers)
For developers, neom_vr serves as an excellent case study for:
•	Experimental Library Integration: Demonstrates how to integrate and experiment with cutting-edge
    (and sometimes less stable) VR-focused Flutter packages like panorama, video_360, and split_view.
•	Mobile VR Development: Provides practical examples of implementing smartphone-based VR experiences,
    including stereoscopic split views.
•	GetX for State Management: Utilizes GetX's Neom360ViewerController for managing reactive state
    related to VR playback and controls.
•	Service Layer Integration: It is designed to implement a Neom360ViewerService interface (defined in neom_core),
    showcasing how experimental functionalities can be exposed through an abstraction.
•	Platform Integration (Custom Tabs): Demonstrates launching external URLs in custom browser tabs for WebVR experiences.
•	Performance Challenges: Highlights the unique performance considerations and optimizations required for mobile VR development.
•	R&D Mindset: Encourages an experimental and research-driven approach to solving complex technical challenges.

How it Supports the Open Neom Initiative
neom_vr is vital to the Open Neom ecosystem and the broader Tecnozenism vision by:
•	Democratizing Immersive Experiences: Directly addresses the goal of making VR accessible to a wider audience,
    aligning with the core philosophy of Open Neom.
•	Pioneering Conscious Technology: Explores how VR can be leveraged for deeper states of meditation, biofeedback visualization,
    and conscious engagement, pushing the boundaries of Tecnozenism.
•	Driving Research & Innovation: Serves as a key module for R&D in neuroscience & digital health,
    providing a platform for experimenting with immersive data visualization and therapeutic VR.
•	Enhancing User Engagement: Offers novel and highly engaging ways for users to interact
    with content and experience digital well-being.
•	Showcasing Ambitious Vision: As an experimental module, it demonstrates Open Neom's commitment to exploring future
    technologies and their application for human flourishing.

🚀 Usage
This module provides routes and UI components for various VR experiences (Neom360ViewerPage, PanoramaView, NeomChromePage,
VideoSection). It is typically accessed from experimental sections of the application or as a proof-of-concept for future integrations.

📦 Dependencies
neom_vr relies on neom_core for core services and data models, and on neom_commons for reusable UI components and utilities.
It directly depends on flutter_custom_tabs, panorama, video_360, and split_view for its core VR functionalities.

🤝 Contributing
We welcome contributions to the neom_vr module! If you're passionate about Virtual Reality, mobile optimization,
immersive experiences, or pioneering new applications for conscious technology, your contributions can significantly
shape the future of Open Neom's most ambitious features. This is a module for innovators and researchers.

To understand the broader architectural context of Open Neom and how neom_vr fits into the overall vision of Tecnozenism,
please refer to the main project's MANIFEST.md.

For guidance on how to contribute to Open Neom and to understand the various levels of learning and engagement possible
within the project, consult our comprehensive guide: Learning Flutter Through Open Neom: A Comprehensive Path.

📄 License
This project is licensed under the Apache License, Version 2.0, January 2004. See the LICENSE file for details.
