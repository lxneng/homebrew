require 'formula'

class OfflineImap < Formula
  homepage 'http://offlineimap.org/'
  url 'https://github.com/downloads/spaetz/offlineimap/offlineimap-v6.5.4.tar.gz'
  sha1 'a9ad5f32f8bc0ec042f8059ea9d34282bb8b682a'

  head 'https://github.com/OfflineIMAP/offlineimap.git'

  def install
    prefix.install 'offlineimap.conf', 'offlineimap.conf.minimal'
    libexec.install 'bin/offlineimap' => 'offlineimap.py'
    libexec.install 'offlineimap'
    bin.install_symlink libexec+'offlineimap.py' => 'offlineimap'
  end

  def caveats; <<-EOS.undent
    To get started, copy one of these configurations to ~/.offlineimaprc:
    * minimal configuration:
        cp -n #{prefix}/offlineimap.conf.minimal ~/.offlineimaprc

    * advanced configuration:
        cp -n #{prefix}/offlineimap.conf ~/.offlineimaprc
    EOS
  end

  def plist; <<-EOS.undent
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
      <dict>
        <key>KeepAlive</key>
        <false/>
        <key>Label</key>
        <string>#{plist_name}</string>
        <key>ProgramArguments</key>
        <array>
          <string>#{opt_prefix}/bin/offlineimap</string>
        </array>
        <key>StartInterval</key>
        <integer>300</integer>
        <key>RunAtLoad</key>
        <true />
        <key>StandardErrorPath</key>
        <string>/dev/null</string>
        <key>StandardOutPath</key>
        <string>/dev/null</string>
      </dict>
    </plist>
    EOS
  end
end
