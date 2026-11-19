cask "jpthecat" do
  version "1.162"
  sha256 "abf21175ffb20ae4d7d9cf13397e0c6331f132d4d11b39417b5b4565f87d5632"

  url "https://github.com/8bittts/JPtheCat/releases/download/v#{version}/JPtheCat-#{version}.dmg"
  name "JP the Cat"
  desc "Menu bar AI coding cost meter"
  homepage "https://github.com/8bittts/JPtheCat"

  livecheck do
    url "https://raw.githubusercontent.com/8bittts/JPtheCat/main/feed/public/stable/appcast.xml"
    strategy :sparkle, &:short_version
  end

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "JPtheCat.app"

  zap trash: [
    "~/Library/Application Support/com.8bittts.jpthecat",
    "~/Library/Application Support/JPtheCat",
    "~/Library/Caches/com.8bittts.jpthecat",
    "~/Library/Caches/com.8bittts.jpthecat.ShipIt",
    "~/Library/Group Containers/GRNGR33Z8A.com.8bittts.jpthecat",
    "~/Library/HTTPStorages/com.8bittts.jpthecat",
    "~/Library/Preferences/com.8bittts.jpthecat.plist",
    "~/Library/Saved Application State/com.8bittts.jpthecat.savedState",
  ]
end
