{ lib
, stdenv
, runCommand
, fetchFromGitHub
, fetchYarnDeps
, writeText
, jq
, yarn
, fixup_yarn_lock
, nodejs
, jitsi-meet
}:

let
  pinData = lib.importJSON ./pin.json;
  noPhoningHome = {
    disable_guests = true; # disable automatic guest account registration at matrix.org
    piwik = false; # disable analytics
  };
in
stdenv.mkDerivation rec {
  pname = "element-web";
  inherit (pinData) version;

  src = fetchFromGitHub {
    owner = "vector-im";
    repo = pname;
    rev = "v${version}";
    sha256 = pinData.webSrcHash;
  };

  offlineCache = fetchYarnDeps {
    yarnLock = src + "/yarn.lock";
    sha256 = pinData.webYarnHash;
  };

  nativeBuildInputs = [ yarn fixup_yarn_lock jq nodejs ];

  configurePhase = ''
    runHook preConfigure

    export HOME=$PWD/tmp
    # with the update of openssl3, some key ciphers are not supported anymore
    # this flag will allow those codecs again as a workaround
    # see https://medium.com/the-node-js-collection/node-js-17-is-here-8dba1e14e382#5f07
    # and https://github.com/vector-im/element-web/issues/21043
    export NODE_OPTIONS=--openssl-legacy-provider
    mkdir -p $HOME

    fixup_yarn_lock yarn.lock
    yarn config --offline set yarn-offline-mirror $offlineCache
    yarn install --offline --frozen-lockfile --ignore-platform --ignore-scripts --no-progress --non-interactive
    patchShebangs node_modules

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    export VERSION=${version}
    yarn build:res --offline
    yarn build:module_system --offline
    yarn build:bundle --offline

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    cp -R webapp $out
    cp ${jitsi-meet}/libs/external_api.min.js $out/jitsi_external_api.min.js
    echo "${version}" > "$out/version"
    jq -s '.[0] * $conf' "config.sample.json" --argjson "conf" '${builtins.toJSON noPhoningHome}' > "$out/config.json"

    runHook postInstall
  '';

  meta = {
    description = "A glossy Matrix collaboration client for the web";
    homepage = "https://element.io/";
    changelog = "https://github.com/vector-im/element-web/blob/v${version}/CHANGELOG.md";
    maintainers = lib.teams.matrix.members;
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
  };
}
