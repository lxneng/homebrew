require 'formula'

class Proxychains < Formula
  url 'http://pkgs.fedoraproject.org/repo/pkgs/proxychains/proxychains-3.1.tar.gz/4629c156001ab70aa7e98960eb513148/proxychains-3.1.tar.gz'
  homepage 'http://proxychains.sourceforge.net/'
  sha1 '3d4ab30c65d4dc21af9898464e5789a09194d04c'

  def patches
    # use os x style dylib
    {:p1 => "https://raw.github.com/ephesus/Proxychains-OS-X-Homebrew-patch/master/proxychains-3.1_osx.diff"}
  end

  def install
    system "./configure", "--disable-debug", "--disable-dependency-tracking",
                          "--prefix=#{prefix}"

    inreplace "proxychains/libproxychains.c" do |s|
      s.gsub!('/etc/proxychains.conf',    "#{etc}/proxychains.conf")
    end

    system "make install"
  end
end
