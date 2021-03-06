require "extend/pathname"
require "keg_fix_install_names"
require "formula_lock"
require "ostruct"

class Keg
  class AlreadyLinkedError < RuntimeError
    def initialize(keg)
      super <<-EOS.undent
        Cannot link #{keg.name}
        Another version is already linked: #{keg.linked_keg_record.resolved_path}
        EOS
    end
  end

  class LinkError < RuntimeError
    attr_reader :keg, :src, :dst

    def initialize(keg, src, dst)
      @src = src
      @dst = dst
      @keg = keg
    end
  end

  class ConflictError < LinkError
    def suggestion
      conflict = Keg.for(dst)
    rescue NotAKegError, Errno::ENOENT
      "already exists. You may want to remove it:\n  rm #{dst}\n"
    else
      <<-EOS.undent
      is a symlink belonging to #{conflict.name}. You can unlink it:
        brew unlink #{conflict.name}
      EOS
    end

    def to_s
      s = []
      s << "Could not symlink #{src}"
      s << "Target #{dst}" << suggestion
      s << <<-EOS.undent
        To force the link and overwrite all conflicting files:
          brew link --overwrite #{keg.name}

        To list all files that would be deleted:
          brew link --overwrite --dry-run #{keg.name}
        EOS
      s.join("\n")
    end
  end

  class DirectoryNotWritableError < LinkError
    def to_s; <<-EOS.undent
      Could not symlink #{src}
      #{dst.dirname} is not writable.
      EOS
    end
  end

  # locale-specific directories have the form language[_territory][.codeset][@modifier]
  LOCALEDIR_RX = /(locale|man)\/([a-z]{2}|C|POSIX)(_[A-Z]{2})?(\.[a-zA-Z\-0-9]+(@.+)?)?/
  INFOFILE_RX = %r[info/([^.].*?\.info|dir)$]
  TOP_LEVEL_DIRECTORIES = %w[bin etc include lib sbin share var Frameworks]
  PRUNEABLE_DIRECTORIES = %w[bin etc include lib sbin share Frameworks LinkedKegs].map do |d|
    case d when 'LinkedKegs' then HOMEBREW_LIBRARY/d else HOMEBREW_PREFIX/d end
  end

  # These paths relative to the keg's share directory should always be real
  # directories in the prefix, never symlinks.
  SHARE_PATHS = %w[
    aclocal doc info locale man
    man/man1 man/man2 man/man3 man/man4
    man/man5 man/man6 man/man7 man/man8
    man/cat1 man/cat2 man/cat3 man/cat4
    man/cat5 man/cat6 man/cat7 man/cat8
    applications gnome gnome/help icons
    mime-info pixmaps sounds
  ]

  # if path is a file in a keg then this will return the containing Keg object
  def self.for path
    path = path.realpath
    while not path.root?
      return Keg.new(path) if path.parent.parent == HOMEBREW_CELLAR.realpath
      path = path.parent.realpath # realpath() prevents root? failing
    end
    raise NotAKegError, "#{path} is not inside a keg"
  end

  attr_reader :path, :name, :linked_keg_record, :opt_record
  protected :path

  def initialize path
    raise "#{path} is not a valid keg" unless path.parent.parent.realpath == HOMEBREW_CELLAR.realpath
    raise "#{path} is not a directory" unless path.directory?
    @path = path
    @name = path.parent.basename.to_s
    @linked_keg_record = HOMEBREW_LIBRARY.join("LinkedKegs", name)
    @opt_record = HOMEBREW_PREFIX.join("opt", name)
  end

  def fname
    opoo "Keg#fname is a deprecated alias for Keg#name and will be removed soon"
    name
  end

  def to_s
    path.to_s
  end

  if Pathname.method_defined?(:to_path)
    alias_method :to_path, :to_s
  else
    alias_method :to_str, :to_s
  end

  def inspect
    "#<#{self.class.name}:#{path}>"
  end

  def ==(other)
    instance_of?(other.class) && path == other.path
  end
  alias_method :eql?, :==

  def hash
    path.hash
  end

  def abv
    path.abv
  end

  def directory?
    path.directory?
  end

  def exist?
    path.exist?
  end

  def /(other)
    path / other
  end

  def join(*args)
    path.join(*args)
  end

  def rename(*args)
    path.rename(*args)
  end

  def linked?
    linked_keg_record.symlink? &&
      linked_keg_record.directory? &&
      path == linked_keg_record.resolved_path
  end

  def remove_linked_keg_record
    linked_keg_record.unlink
    linked_keg_record.parent.rmdir_if_possible
  end

  def optlinked?
    opt_record.symlink? && path == opt_record.resolved_path
  end

  def remove_opt_record
    opt_record.unlink
    opt_record.parent.rmdir_if_possible
  end

  def uninstall
    path.rmtree
    path.parent.rmdir_if_possible
    remove_opt_record if optlinked?
  end

  def unlink
    ObserverPathnameExtension.reset_counts!

    dirs = []

    TOP_LEVEL_DIRECTORIES.map{ |d| path.join(d) }.each do |dir|
      next unless dir.exist?
      dir.find do |src|
        dst = HOMEBREW_PREFIX + src.relative_path_from(path)
        dst.extend(ObserverPathnameExtension)

        dirs << dst if dst.directory? && !dst.symlink?

        # check whether the file to be unlinked is from the current keg first
        if dst.symlink? && src == dst.resolved_path
          dst.uninstall_info if dst.to_s =~ INFOFILE_RX
          dst.unlink
          Find.prune if src.directory?
        end
      end
    end

    remove_linked_keg_record if linked?

    dirs.reverse_each(&:rmdir_if_possible)

    ObserverPathnameExtension.total
  end

  def lock
    FormulaLock.new(name).with_lock { yield }
  end

  def completion_installed? shell
    dir = case shell
          when :bash then path.join("etc", "bash_completion.d")
          when :zsh  then path.join("share", "zsh", "site-functions")
          end
    dir && dir.directory? && dir.children.any?
  end

  def plist_installed?
    Dir["#{path}/*.plist"].any?
  end

  def python_site_packages_installed?
    path.join("lib", "python2.7", "site-packages").directory?
  end

  def app_installed?
    Dir["#{path}/{,libexec/}*.app"].any?
  end

  def version
    require 'pkg_version'
    PkgVersion.parse(path.basename.to_s)
  end

  def find(*args, &block)
    path.find(*args, &block)
  end

  def link mode=OpenStruct.new
    raise AlreadyLinkedError.new(self) if linked_keg_record.directory?

    ObserverPathnameExtension.reset_counts!

    # yeah indeed, you have to force anything you need in the main tree into
    # these dirs REMEMBER that *NOT* everything needs to be in the main tree
    link_dir('etc', mode) {:mkpath}
    link_dir('bin', mode) {:skip_dir}
    link_dir('sbin', mode) {:skip_dir}
    link_dir('include', mode) {:link}

    link_dir('share', mode) do |path|
      case path.to_s
      when 'locale/locale.alias' then :skip_file
      when INFOFILE_RX then :info
      when LOCALEDIR_RX then :mkpath
      when *SHARE_PATHS then :mkpath
      when /^icons\/.*\/icon-theme\.cache$/ then :skip_file
      # all icons subfolders should also mkpath
      when /^icons\// then :mkpath
      when /^zsh/ then :mkpath
      else :link
      end
    end

    link_dir('lib', mode) do |path|
      case path.to_s
      when 'charset.alias' then :skip_file
      # pkg-config database gets explicitly created
      when 'pkgconfig' then :mkpath
      # lib/language folders also get explicitly created
      when 'dtrace' then :mkpath
      when /^gdk-pixbuf/ then :mkpath
      when 'ghc' then :mkpath
      when 'lua' then :mkpath
      when /^node/ then :mkpath
      when /^ocaml/ then :mkpath
      when /^perl5/ then :mkpath
      when 'php' then :mkpath
      when /^python[23]\.\d/ then :mkpath
      when 'ruby' then :mkpath
      # Everything else is symlinked to the cellar
      else :link
      end
    end

    link_dir('Frameworks', mode) do |path|
      # Frameworks contain symlinks pointing into a subdir, so we have to use
      # the :link strategy. However, for Foo.framework and
      # Foo.framework/Versions we have to use :mkpath so that multiple formulae
      # can link their versions into it and `brew [un]link` works.
      if path.to_s =~ /[^\/]*\.framework(\/Versions)?$/
        :mkpath
      else
        :link
      end
    end

    unless mode.dry_run
      make_relative_symlink(linked_keg_record, path, mode)
      optlink(mode)
    end
  rescue LinkError
    unlink
    raise
  else
    ObserverPathnameExtension.total
  end

  def optlink(mode=OpenStruct.new)
    opt_record.delete if opt_record.symlink? || opt_record.exist?
    make_relative_symlink(opt_record, path, mode)
  end

  def delete_pyc_files!
    find { |pn| pn.delete if pn.extname == ".pyc" }
  end

  private

  def resolve_any_conflicts dst, mode
    src = dst.resolved_path
    # src itself may be a symlink, so check lstat to ensure we are dealing with
    # a directory, and not a symlink pointing at a directory (which needs to be
    # treated as a file). In other words, we only want to resolve one symlink.
    # If it isn't a directory, make_relative_symlink will raise an exception.
    if dst.symlink? && src.lstat.directory?
      keg = Keg.for(src)
      dst.unlink unless mode.dry_run
      keg.link_dir(src, mode) { :mkpath }
      return true
    end
  rescue NotAKegError
    puts "Won't resolve conflicts for symlink #{dst} as it doesn't resolve into the Cellar" if ARGV.verbose?
  end

  def make_relative_symlink dst, src, mode
    if dst.symlink? && src == dst.resolved_path
      puts "Skipping; link already exists: #{dst}" if ARGV.verbose?
      return
    end

    # cf. git-clean -n: list files to delete, don't really link or delete
    if mode.dry_run and mode.overwrite
      if dst.symlink?
        puts "#{dst} -> #{dst.resolved_path}"
      elsif dst.exist?
        puts dst
      end
      return
    end

    # list all link targets
    if mode.dry_run
      puts dst
      return
    end

    dst.delete if mode.overwrite && (dst.exist? || dst.symlink?)
    dst.make_relative_symlink(src)
  rescue Errno::EEXIST
    if dst.exist?
      raise ConflictError.new(self, src.relative_path_from(path), dst)
    elsif dst.symlink?
      dst.unlink
      retry
    end
  rescue Errno::EACCES
    raise DirectoryNotWritableError.new(self, src.relative_path_from(path), dst)
  rescue SystemCallError
    raise LinkError.new(self, src.relative_path_from(path), dst)
  end

  protected

  # symlinks the contents of path+relative_dir recursively into #{HOMEBREW_PREFIX}/relative_dir
  def link_dir relative_dir, mode
    root = path+relative_dir
    return unless root.exist?
    root.find do |src|
      next if src == root
      dst = HOMEBREW_PREFIX + src.relative_path_from(path)
      dst.extend ObserverPathnameExtension

      if src.symlink? || src.file?
        Find.prune if File.basename(src) == '.DS_Store'
        # Don't link pyc files because Python overwrites these cached object
        # files and next time brew wants to link, the pyc file is in the way.
        if src.extname == '.pyc' && src.to_s =~ /site-packages/
          Find.prune
        end

        case yield src.relative_path_from(root)
        when :skip_file, nil
          Find.prune
        when :info
          next if File.basename(src) == 'dir' # skip historical local 'dir' files
          make_relative_symlink dst, src, mode
          dst.install_info
        else
          make_relative_symlink dst, src, mode
        end
      elsif src.directory?
        # if the dst dir already exists, then great! walk the rest of the tree tho
        next if dst.directory? and not dst.symlink?
        # no need to put .app bundles in the path, the user can just use
        # spotlight, or the open command and actual mac apps use an equivalent
        Find.prune if src.extname == '.app'

        case yield src.relative_path_from(root)
        when :skip_dir
          Find.prune
        when :mkpath
          dst.mkpath unless resolve_any_conflicts(dst, mode)
        else
          unless resolve_any_conflicts(dst, mode)
            make_relative_symlink dst, src, mode
            Find.prune
          end
        end
      end
    end
  end
end
