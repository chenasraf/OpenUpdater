# Changelog

## [0.6.0](https://github.com/chenasraf/OpenUpdater/compare/v0.5.0...v0.6.0) (2026-06-22)


### Features

* **recipe:** WezTerm (`com.github.wez.wezterm`) read version via `wezterm --version` ([1ec79b9](https://github.com/chenasraf/OpenUpdater/commit/1ec79b9fcfa8d8e8afc1a642ff834c238d5c2430))
* **updating:** installed_version can read a plist key, not just a command ([a408864](https://github.com/chenasraf/OpenUpdater/commit/a408864395200d953014ef5f396bc3e7bb082aa8))
* **updating:** read installed version from a bundled binary via recipe ([ec05279](https://github.com/chenasraf/OpenUpdater/commit/ec05279daaec0f23b0c1e724bb76a26fdc3d698c))


### Bug Fixes

* **recipe:** Zoom (`us.zoom.xos`) compare against CFBundleVersion ([09c200f](https://github.com/chenasraf/OpenUpdater/commit/09c200f983b197bd1ac9d25514c0fd93187b48c9))

## [0.5.0](https://github.com/chenasraf/OpenUpdater/compare/v0.4.0...v0.5.0) (2026-06-22)


### Features

* **updating:** check for updates at launch by default ([6f7adaa](https://github.com/chenasraf/OpenUpdater/commit/6f7adaae264b74fa7180f7f0b3147d8e7663cf55))


### Bug Fixes

* **helper:** re-register stale helper before privileged installs ([c52928e](https://github.com/chenasraf/OpenUpdater/commit/c52928e36c40e8ffe15d454f24b5bb0cc0feb181))
* **helper:** surface stale helper for reinstall instead of breaking it ([97d660a](https://github.com/chenasraf/OpenUpdater/commit/97d660ab4010d99726531f78ec7a478fec1e41a9))
* **installer:** retry root-owned app replace through privileged helper ([4287ec1](https://github.com/chenasraf/OpenUpdater/commit/4287ec12d5e69b163d1e43b3af2a0292baa01417))
* **updating:** treat blank plist strings as missing in app scan ([59b349a](https://github.com/chenasraf/OpenUpdater/commit/59b349a5e74264696048eb47609f4118b0ae540a))

## [0.4.0](https://github.com/chenasraf/OpenUpdater/compare/v0.3.0...v0.4.0) (2026-06-22)


### Features

* **menubar:** show available-update count next to the icon ([c0e078b](https://github.com/chenasraf/OpenUpdater/commit/c0e078bdac91e6a0921b8fe71147980ae6bf8282))
* **recipe:** Blender (`org.blenderfoundation.blender`) add LTS channel ([24f758f](https://github.com/chenasraf/OpenUpdater/commit/24f758f00a53124be3cccb86c7804f4a9b2ea541))
* **recipe:** Blender (`org.blenderfoundation.blender`) track LTS series dynamically ([b1db30a](https://github.com/chenasraf/OpenUpdater/commit/b1db30a1830d7d885919b5f6a6aeb56583aa7517))
* **recipe:** Firefox (`org.mozilla.firefox`) add ESR channel ([68f86bf](https://github.com/chenasraf/OpenUpdater/commit/68f86bfd9f0dc6fbcdd8dae0e4a53939f0ced9da))
* **recipe:** LibreOffice (`org.libreoffice.script`) add Fresh/Still channels ([a72b0e8](https://github.com/chenasraf/OpenUpdater/commit/a72b0e8f85df4a3ba387f9932a4605946d5e12af))
* **recipe:** Thunderbird (`org.mozilla.thunderbird`) ([8bbd865](https://github.com/chenasraf/OpenUpdater/commit/8bbd865512e91abc14164cab479b394cffabb552))
* **recipe:** Wireshark (`org.wireshark.Wireshark`) ([a857fad](https://github.com/chenasraf/OpenUpdater/commit/a857fad07e4c33e7ddbdad5f846ec48c800f5d15))
* **updating:** confirm before quitting open apps to update them ([e921f02](https://github.com/chenasraf/OpenUpdater/commit/e921f02d8d95237ceed42fa2338dae5333e5735d))
* **updating:** periodic update checks with selectable frequency ([a0fb11e](https://github.com/chenasraf/OpenUpdater/commit/a0fb11e58fbebd7787a8537bc51e8ef791c450f5))
* **updating:** resolve placeholders from other pages and select:latest for HTTP checks ([33febce](https://github.com/chenasraf/OpenUpdater/commit/33febcef2ae469e5a34ce7c0ac5298ba9ba9a7e7))
* **updating:** selectable release channels (ESR/LTS/etc.) per app ([bbb4622](https://github.com/chenasraf/OpenUpdater/commit/bbb46224fbf3413e56277cdf231e9bc90a119e5e))


### Bug Fixes

* **settings:** restore link color for the GitHub token link ([13ad8e9](https://github.com/chenasraf/OpenUpdater/commit/13ad8e9253b797d354cd98295af8a113948f21f0))

## [0.3.0](https://github.com/chenasraf/OpenUpdater/compare/v0.2.0...v0.3.0) (2026-06-22)


### Features

* **ui:** move ignore list and unsupported apps into the main window ([978d250](https://github.com/chenasraf/OpenUpdater/commit/978d25098be31bb0a643d4d16c2f697f9a2711af))
* **updates:** add Stop button to halt the update queue ([6ca26f2](https://github.com/chenasraf/OpenUpdater/commit/6ca26f205bb1bb2ff1cbfa73c4f2cc67a829b342))


### Bug Fixes

* **installer:** accept long DMG license agreements (PAGER=cat) ([2dc820d](https://github.com/chenasraf/OpenUpdater/commit/2dc820da527eddb0e05f1c0ab9f30ec98fd6ec42))
* **installer:** keep source extension so pkg installs work ([961a6a9](https://github.com/chenasraf/OpenUpdater/commit/961a6a98d016ef5be4abd949de97a4b3b72ce37f))
* **recipe:** Firefox (`org.mozilla.firefox`) ([08e02c6](https://github.com/chenasraf/OpenUpdater/commit/08e02c674771b4e23595e76ba68f2a2fd8b63b82))
* **recipe:** Google Chrome (`com.google.Chrome`) ([aedb59e](https://github.com/chenasraf/OpenUpdater/commit/aedb59e8338eb0345ecf660198c29e6513e8e817))
* **recipe:** Visual Studio Code (`com.microsoft.VSCode`) ([49f19f5](https://github.com/chenasraf/OpenUpdater/commit/49f19f53b0b1fe71a69fcb61631bc0578499d940))

## [0.2.0](https://github.com/chenasraf/OpenUpdater/compare/v0.1.0...v0.2.0) (2026-06-21)


### Features

* open at startup + open main window on launch ([ad56850](https://github.com/chenasraf/OpenUpdater/commit/ad568507cb9a9f98a11f11d6a11211e8d1c63cf1))

## [0.1.0](https://github.com/chenasraf/OpenUpdater/compare/v0.1.0...v0.1.0) (2026-06-21)


### Features

* add app icon ([053166f](https://github.com/chenasraf/OpenUpdater/commit/053166f925dc3998df990694ff035f895adb9d1e))
* add issue tempates, add request button to unsupported apps ([c7240b5](https://github.com/chenasraf/OpenUpdater/commit/c7240b5c56ed5e642d92e8a717003d270c86ce2d))
* add recipe for Firefox (`org.mozilla.firefox`) ([af67625](https://github.com/chenasraf/OpenUpdater/commit/af67625ad6613352514f6d3ee571afac00cc5af3))
* add recipe for Google Chrome (`com.google.Chrome`) ([1afaea6](https://github.com/chenasraf/OpenUpdater/commit/1afaea6794f8df18ec6d425e60f7ea1763edff70))
* add recipe for Stremio (`com.westbridge.stremio5-mac`) ([e0d2ef6](https://github.com/chenasraf/OpenUpdater/commit/e0d2ef6b402b852c080dac90b1c586b0f5f223c3))
* add recipe for Studio 3T (`com.install4j.0526-4458-1435-8154.837`) ([c372b99](https://github.com/chenasraf/OpenUpdater/commit/c372b997ca47e41a2a0651c724576b59d27612a8))
* add recipe for VS Code (`com.microsoft.VSCode`) ([13fed0e](https://github.com/chenasraf/OpenUpdater/commit/13fed0eb8950c1b477c0da56252c2f6f4bb1b879))
* add self-update via sparkle ([2ef2e35](https://github.com/chenasraf/OpenUpdater/commit/2ef2e35ee7180b90ba9f2c0f7b036faa6f9c934d))
* add timeouts for installs, cache icons ([27ef4b2](https://github.com/chenasraf/OpenUpdater/commit/27ef4b2cd9503537385c60010ff989b255841628))
* app store update check ([e32b33a](https://github.com/chenasraf/OpenUpdater/commit/e32b33a4e35ea43a201a7b1b899be8ccc07d77a3))
* cache update check results on disk ([8ae6012](https://github.com/chenasraf/OpenUpdater/commit/8ae601280a97c2aedc9c62f73521d9efc476a697))
* cancel app updates mid-flight ([94b7a99](https://github.com/chenasraf/OpenUpdater/commit/94b7a997eca42168f2dd92c3ab36e7cf6f63d283))
* detect and ignore steam and built-in apple apps ([7725ba7](https://github.com/chenasraf/OpenUpdater/commit/7725ba78b6f5cda1f4973158a9a9e37fb5616ea3))
* github + sparkle update checkers ([366ff19](https://github.com/chenasraf/OpenUpdater/commit/366ff19c9628e00c3c84f9c0cd34232263959536))
* ignore apps/versions ([bbe63ca](https://github.com/chenasraf/OpenUpdater/commit/bbe63cac5ec633595362ec6fedac8fa040a52ff6))
* immediately hid app after upate ([9f4caec](https://github.com/chenasraf/OpenUpdater/commit/9f4caec21fdd0bb5cf3b169a35659514dd8c8ea6))
* improve error detection, add version separate placeholders ([1349208](https://github.com/chenasraf/OpenUpdater/commit/134920830bc580f837da4d54d91e44fc099ce590))
* initial app UI + app list ([f4899cf](https://github.com/chenasraf/OpenUpdater/commit/f4899cfbc71a0aa037504da222282771b8918e0a))
* manual update dialog ([b472da4](https://github.com/chenasraf/OpenUpdater/commit/b472da40a6ff415c24a0d74970ad1adf48bd3afd))
* more recipes ([8f0855c](https://github.com/chenasraf/OpenUpdater/commit/8f0855c112c2a7b433c998747392597486ead88d))
* more recipes, http/yaml source types ([39f7778](https://github.com/chenasraf/OpenUpdater/commit/39f777881a01d8fd3d6bf644eb40a236d6051fdd))
* multi select + update ([3bfa267](https://github.com/chenasraf/OpenUpdater/commit/3bfa267ad3a20a7a76cd1963f3b9da72f11e3a79))
* multi-selection context menu ([d4a2000](https://github.com/chenasraf/OpenUpdater/commit/d4a20002fbcd807ecc4b29fb2c3cbbf2f6f54a4f))
* override prerelease option in context menu ([f41788d](https://github.com/chenasraf/OpenUpdater/commit/f41788d6ee5f0eaa962bb7e93bec5fbfbccfb9d6))
* privileged helper ([219c3a0](https://github.com/chenasraf/OpenUpdater/commit/219c3a094dd7869bd963262f3ef970fcf535c419))
* re-scan individual app ([dbd5276](https://github.com/chenasraf/OpenUpdater/commit/dbd5276ee893727137c021c26436dcd2c25136d5))
* settings with github token field, more recipes, pkg support ([70b22a6](https://github.com/chenasraf/OpenUpdater/commit/70b22a62fe9ee8817a2dcb4d09ae4b62dea4a1ae))
* show dock icon when main window open ([06fc9e2](https://github.com/chenasraf/OpenUpdater/commit/06fc9e2ca2829ea602a28f2d23ee076c78b20132))
* show error details on failure ([d478669](https://github.com/chenasraf/OpenUpdater/commit/d4786697332287becb66f608dde92c2b895127e5))
* split ignore list view ([57082b9](https://github.com/chenasraf/OpenUpdater/commit/57082b9885bc3c0060390193ce7f2e399a6b823c))
* support custom recipes ([b2c3639](https://github.com/chenasraf/OpenUpdater/commit/b2c36393a59081f9fb39ea2f5dd714d4e684a389))
* tag ignore/pattern in github releases, more recipes ([c6859df](https://github.com/chenasraf/OpenUpdater/commit/c6859df24d650c3a29a4c62a3b96e1b7f95b7c82))
* unquarantine, progress bar, quit before replace + relaunch ([7222508](https://github.com/chenasraf/OpenUpdater/commit/7222508e6d9053df41f269e43fb08c2b3f298ebd))
* unsupported list + export/report ([252da67](https://github.com/chenasraf/OpenUpdater/commit/252da67ffef8f304d13d41dd52f8cf09914b3fdc))
* update ignore list + allow yml to override ignore ([ec604e9](https://github.com/chenasraf/OpenUpdater/commit/ec604e9b51ddf59b9c85e180b02232e63dc90383))
* update menubar window design ([b50a937](https://github.com/chenasraf/OpenUpdater/commit/b50a937e394fdf7d95e44556bc1b41661fbfc474))
* walk subdirectories in /Applications and ~/Applications ([c1663bb](https://github.com/chenasraf/OpenUpdater/commit/c1663bb1f8a60aa8965644b1ead212e4d4df4f30))


### Performance Improvements

* isolate hdiutils/ditto to avoid freezing ui thread ([894f379](https://github.com/chenasraf/OpenUpdater/commit/894f379ed9a68e389a36185d2cd3079f1f4205ee))

## [0.1.0](https://github.com/chenasraf/OpenUpdater/compare/OpenUpdater-v1.0.0...OpenUpdater-v0.1.0) (2026-06-21)


### Features

* add app icon ([053166f](https://github.com/chenasraf/OpenUpdater/commit/053166f925dc3998df990694ff035f895adb9d1e))
* add issue tempates, add request button to unsupported apps ([c7240b5](https://github.com/chenasraf/OpenUpdater/commit/c7240b5c56ed5e642d92e8a717003d270c86ce2d))
* add recipe for Firefox (`org.mozilla.firefox`) ([af67625](https://github.com/chenasraf/OpenUpdater/commit/af67625ad6613352514f6d3ee571afac00cc5af3))
* add recipe for Google Chrome (`com.google.Chrome`) ([1afaea6](https://github.com/chenasraf/OpenUpdater/commit/1afaea6794f8df18ec6d425e60f7ea1763edff70))
* add recipe for Stremio (`com.westbridge.stremio5-mac`) ([e0d2ef6](https://github.com/chenasraf/OpenUpdater/commit/e0d2ef6b402b852c080dac90b1c586b0f5f223c3))
* add recipe for Studio 3T (`com.install4j.0526-4458-1435-8154.837`) ([c372b99](https://github.com/chenasraf/OpenUpdater/commit/c372b997ca47e41a2a0651c724576b59d27612a8))
* add recipe for VS Code (`com.microsoft.VSCode`) ([13fed0e](https://github.com/chenasraf/OpenUpdater/commit/13fed0eb8950c1b477c0da56252c2f6f4bb1b879))
* add timeouts for installs, cache icons ([27ef4b2](https://github.com/chenasraf/OpenUpdater/commit/27ef4b2cd9503537385c60010ff989b255841628))
* app store update check ([e32b33a](https://github.com/chenasraf/OpenUpdater/commit/e32b33a4e35ea43a201a7b1b899be8ccc07d77a3))
* cache update check results on disk ([8ae6012](https://github.com/chenasraf/OpenUpdater/commit/8ae601280a97c2aedc9c62f73521d9efc476a697))
* cancel app updates mid-flight ([94b7a99](https://github.com/chenasraf/OpenUpdater/commit/94b7a997eca42168f2dd92c3ab36e7cf6f63d283))
* detect and ignore steam and built-in apple apps ([7725ba7](https://github.com/chenasraf/OpenUpdater/commit/7725ba78b6f5cda1f4973158a9a9e37fb5616ea3))
* github + sparkle update checkers ([366ff19](https://github.com/chenasraf/OpenUpdater/commit/366ff19c9628e00c3c84f9c0cd34232263959536))
* ignore apps/versions ([bbe63ca](https://github.com/chenasraf/OpenUpdater/commit/bbe63cac5ec633595362ec6fedac8fa040a52ff6))
* immediately hid app after upate ([9f4caec](https://github.com/chenasraf/OpenUpdater/commit/9f4caec21fdd0bb5cf3b169a35659514dd8c8ea6))
* improve error detection, add version separate placeholders ([1349208](https://github.com/chenasraf/OpenUpdater/commit/134920830bc580f837da4d54d91e44fc099ce590))
* initial app UI + app list ([f4899cf](https://github.com/chenasraf/OpenUpdater/commit/f4899cfbc71a0aa037504da222282771b8918e0a))
* manual update dialog ([b472da4](https://github.com/chenasraf/OpenUpdater/commit/b472da40a6ff415c24a0d74970ad1adf48bd3afd))
* more recipes ([8f0855c](https://github.com/chenasraf/OpenUpdater/commit/8f0855c112c2a7b433c998747392597486ead88d))
* more recipes, http/yaml source types ([39f7778](https://github.com/chenasraf/OpenUpdater/commit/39f777881a01d8fd3d6bf644eb40a236d6051fdd))
* multi select + update ([3bfa267](https://github.com/chenasraf/OpenUpdater/commit/3bfa267ad3a20a7a76cd1963f3b9da72f11e3a79))
* multi-selection context menu ([d4a2000](https://github.com/chenasraf/OpenUpdater/commit/d4a20002fbcd807ecc4b29fb2c3cbbf2f6f54a4f))
* override prerelease option in context menu ([f41788d](https://github.com/chenasraf/OpenUpdater/commit/f41788d6ee5f0eaa962bb7e93bec5fbfbccfb9d6))
* privileged helper ([219c3a0](https://github.com/chenasraf/OpenUpdater/commit/219c3a094dd7869bd963262f3ef970fcf535c419))
* re-scan individual app ([dbd5276](https://github.com/chenasraf/OpenUpdater/commit/dbd5276ee893727137c021c26436dcd2c25136d5))
* settings with github token field, more recipes, pkg support ([70b22a6](https://github.com/chenasraf/OpenUpdater/commit/70b22a62fe9ee8817a2dcb4d09ae4b62dea4a1ae))
* show dock icon when main window open ([06fc9e2](https://github.com/chenasraf/OpenUpdater/commit/06fc9e2ca2829ea602a28f2d23ee076c78b20132))
* show error details on failure ([d478669](https://github.com/chenasraf/OpenUpdater/commit/d4786697332287becb66f608dde92c2b895127e5))
* split ignore list view ([57082b9](https://github.com/chenasraf/OpenUpdater/commit/57082b9885bc3c0060390193ce7f2e399a6b823c))
* support custom recipes ([b2c3639](https://github.com/chenasraf/OpenUpdater/commit/b2c36393a59081f9fb39ea2f5dd714d4e684a389))
* tag ignore/pattern in github releases, more recipes ([c6859df](https://github.com/chenasraf/OpenUpdater/commit/c6859df24d650c3a29a4c62a3b96e1b7f95b7c82))
* unquarantine, progress bar, quit before replace + relaunch ([7222508](https://github.com/chenasraf/OpenUpdater/commit/7222508e6d9053df41f269e43fb08c2b3f298ebd))
* unsupported list + export/report ([252da67](https://github.com/chenasraf/OpenUpdater/commit/252da67ffef8f304d13d41dd52f8cf09914b3fdc))
* update ignore list + allow yml to override ignore ([ec604e9](https://github.com/chenasraf/OpenUpdater/commit/ec604e9b51ddf59b9c85e180b02232e63dc90383))
* update menubar window design ([b50a937](https://github.com/chenasraf/OpenUpdater/commit/b50a937e394fdf7d95e44556bc1b41661fbfc474))
* walk subdirectories in /Applications and ~/Applications ([c1663bb](https://github.com/chenasraf/OpenUpdater/commit/c1663bb1f8a60aa8965644b1ead212e4d4df4f30))


### Performance Improvements

* isolate hdiutils/ditto to avoid freezing ui thread ([894f379](https://github.com/chenasraf/OpenUpdater/commit/894f379ed9a68e389a36185d2cd3079f1f4205ee))
