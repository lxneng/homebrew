require 'formula'

class Libevent < Formula
  url "https://github.com/downloads/libevent/libevent/libevent-2.0.14-stable.tar.gz"
  homepage 'http://www.monkey.org/~provos/libevent/'
  md5 'cac0f379da35d3b98f83ac16fcfe1df4'
  head 'git://github.com/libevent/libevent.git'

  fails_with_llvm "Undefined symbol '_current_base' reported during linking.", :build => 2326

  def install
    ENV.j1 # Needed for Mac Pro compilation
    system "./autogen.sh" if ARGV.build_head?
    system "./configure", "--prefix=#{prefix}"
    system "make install"
  end
end
