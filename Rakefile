# Copyright (c) 2010-2014 The Mirah project authors. All Rights Reserved.
# All contributing project authors may be found in the NOTICE file.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
begin
  require 'bundler/setup'
rescue LoadError
  puts "couldn't load bundler. Check your environment."
end
require 'rake'
require 'rake/testtask'
require 'rubygems'
require 'rubygems/package_task'
require 'java'
require 'jruby/compiler'
require 'ant'

#TODO update downloads st build reqs that are not run reqs go in a different dir
# put run reqs in javalib
# final artifacts got in dist

# this definition ensures that the bootstrap tasks will be completed before
# building the .gem file. Otherwise, the gem may not contain the jars.
task :gem => :compile

# depends on dist/mirahc.jar
Gem::PackageTask.new Gem::Specification.load('mirah.gemspec') do |pkg|
  pkg.need_zip = true
  pkg.need_tar = true
end

task :default => :new_ci

desc "run new backend ci"
task :new_ci => [:'test:core', :'test:jvm', :'test:artifacts', 'dist/mirahc3.jar']

def run_tests tests
  results = tests.map do |name|
    begin
      Rake.application[name].invoke
    rescue Exception => ex
      puts "test: #{name} failed: #{ex} #{ex.backtrace.join "\n"}"
    end
  end

  tests.zip(results).each do |name, passed|
    unless passed
      puts "Errors in #{name}"
    end
  end
  fail if results.any?{|passed|!passed}
end

desc "run full test suite"
task :test do
  run_tests [ 'test:core', 'test:plugins', 'test:jvm', 'test:artifacts' ]
end

namespace :test do

  desc "run the core tests"
  Rake::TestTask.new :core  => :compile do |t|
    t.libs << 'test'
    t.test_files = FileList["test/core/**/*test.rb"]
    java.lang.System.set_property("jruby.duby.enabled", "true")
  end

  desc "run tests for plugins"
  Rake::TestTask.new :plugins  => :compile do |t|
    t.libs << 'test'
    t.test_files = FileList["test/plugins/**/*test.rb"]
    java.lang.System.set_property("jruby.duby.enabled", "true")
  end

  desc "run the artifact tests"
  Rake::TestTask.new :artifacts  => :compile do |t|
    t.libs << 'test'
    t.test_files = FileList["test/artifacts/**/*test.rb"]
  end


  desc "run jvm tests"
  task :jvm => 'test:jvm:all'

  namespace :jvm do
    task :test_setup =>  [:clean_tmp_test_classes, :build_test_fixtures]

    desc "run jvm tests using the new self hosted backend"
    task :all do
      run_tests ["test:jvm:mirror_compilation", "test:jvm:mirrors"]
    end

    desc "run tests for mirror type system"
    Rake::TestTask.new :mirrors  => "dist/mirahc.jar" do |t|
      t.libs << 'test'
      t.test_files = FileList["test/mirrors/**/*test.rb"]
    end

    Rake::TestTask.new :mirror_compilation  => ["dist/mirahc.jar", :test_setup] do |t|
      t.libs << 'test' << 'test/jvm'
      t.ruby_opts.concat ["-r", "new_backend_test_helper"]
      t.test_files = FileList["test/jvm/**/*test.rb"]
    end

    Rake::TestTask.new :modifiers  => ["dist/mirahc.jar", :test_setup] do |t|
      t.libs << 'test' << 'test/jvm'
      t.ruby_opts.concat ["-r", "new_backend_test_helper"]
      t.test_files = FileList["test/jvm/**/modifiers_test.rb"]
    end

  end
end

task :clean_tmp_test_classes do
  FileUtils.rm_rf "tmp_test/test_classes"
  FileUtils.mkdir_p "tmp_test/test_classes"
end



task :build_test_fixtures => 'tmp_test/fixtures/fixtures_built.txt'
directory 'tmp_test/fixtures'

file 'tmp_test/fixtures/fixtures_built.txt' => ['tmp_test/fixtures'] + Dir['test/fixtures/**/*.java'] do

  javac_args = {
      'destdir' => "tmp_test/fixtures",
      'srcdir' => 'test/fixtures',
      'includeantruntime' => false,
      'debug' => true,
      'listfiles' => true
  }
  jvm_version = java.lang.System.getProperty('java.specification.version').to_f

  javac_args['excludes'] = '**/*Java8.java' if jvm_version < 1.8
  ant.javac javac_args
  `touch tmp_test/fixtures/fixtures_built.txt`
end

task :init do
  mkdir_p 'dist'
  mkdir_p 'build'
end

desc "clean up build artifacts"
task :clean do
  ant.delete 'quiet' => true, 'dir' => 'build'
  ant.delete 'quiet' => true, 'dir' => 'dist'
  rm_f 'dist/mirahc.jar'
  rm_rf 'tmp'
  rm_rf 'tmp_test'
  rm_rf 'pkg'
end

desc "clean mirah prev"
task :clean_mirah_prev do
  rm_f 'javalib/mirahc-prev.jar'
end

desc "clean downloaded dependencies"
task :clean_downloads => 'javalib/mirahc-prev.jar' do
  rm_f 'javalib/jruby-complete.jar'
  rm_f 'javalib/asm-5.jar'
  rm_f 'javalib/mirah-asm-5.jar'
  rm_f 'javalib/jarjar.jar'
end

task :compile, [:verbose] => 'dist/mirahc.jar'
task :jvm_backend => 'dist/mirahc.jar'

desc "build backwards-compatible ruby jar"
task :jar,[:verbose] => :compile do |task, args|
  ant.jar 'jarfile' => 'dist/mirah.jar' do
    fileset 'dir' => 'lib'
    fileset 'dir' => 'build'
    fileset 'dir' => '.', 'includes' => 'bin/*'
    zipfileset 'src' => 'dist/mirahc.jar'
    manifest do
      attribute 'name' => 'Main-Class', 'value' => 'org.mirah.MirahCommand'
    end
  end
end

namespace :jar do
  desc "build self-contained, complete ruby jar"
  task :complete => [:jar, 'javalib/mirah-asm-5.jar'] do
    ant.jar 'jarfile' => 'dist/mirah-complete.jar' do
      zipfileset 'src' => 'dist/mirah.jar'
      zipfileset 'src' => 'javalib/mirah-asm-5.jar'
      manifest do
        attribute 'name' => 'Main-Class', 'value' => 'org.mirah.MirahCommand'
      end
    end
  end
end

desc "Build a distribution zip file"
task :zip => 'jar:complete' do
  $CLASSPATH << "dist/mirahc.jar"
  java_import "org.mirah.tool.Mirahc"
  basedir = "tmp/mirah-#{Mirahc::VERSION}"
  mkdir_p "#{basedir}/lib"
  mkdir_p "#{basedir}/bin"
  cp 'dist/mirah-complete.jar', "#{basedir}/lib"
  cp 'distbin/mirah.bash', "#{basedir}/bin/mirah"
  cp 'distbin/mirahc.bash', "#{basedir}/bin/mirahc"
  cp Dir['{distbin/*.bat}'], "#{basedir}/bin/"
  cp_r 'examples', "#{basedir}/examples"
  rm_rf "#{basedir}/examples/wiki"
  cp 'README.md', "#{basedir}"
  cp 'NOTICE', "#{basedir}"
  cp 'LICENSE', "#{basedir}"
  cp 'COPYING', "#{basedir}"
  cp 'History.txt', "#{basedir}"
  sh "sh -c 'cd tmp ; zip -r ../dist/mirah-#{Mirahc::VERSION}.zip mirah-#{Mirahc::VERSION}/*'"
  rm_rf 'tmp'
end

desc "Build java stub"
task :stub => [:compile, 'dist/mirahc-stub.jar']

desc "Build all redistributable files"
task :dist => [:gem, :zip]

file_create 'javalib/mirah-asm-5.jar' => 'javalib/jarjar.jar' do
  require 'open-uri'
  puts "Downloading asm-5.jar"
  url = 'https://search.maven.org/remotecontent?filepath=org/ow2/asm/asm-all/5.0.4/asm-all-5.0.4.jar'
  open(url, 'rb') do |src|
    open('javalib/asm-5.jar', 'wb') do |dest|
      dest.write(src.read)
    end
  end
  run_jar('javalib/jarjar.jar',
          'process',
          'javalib/rename-asm.jarjar',
          'javalib/asm-5.jar',
          'javalib/mirah-asm-5.jar')
end

file_create 'javalib/mirahc-prev.jar' do
  require 'open-uri'

  url = ENV['MIRAH_PREV_PATH'] || 'https://search.maven.org/remotecontent?filepath=org/mirah/mirah/0.1.3/mirah-0.1.3.jar'

  puts "Downloading mirahc-prev.jar from #{url}"

  open(url, 'rb') do |src|
    open('javalib/mirahc-prev.jar', 'wb') do |dest|
      dest.write(src.read)
    end
  end
end

file_create 'javalib/jarjar.jar' do
  require 'open-uri'
  puts "Downloading jarjar.jar"
  url = 'https://search.maven.org/remotecontent?filepath=com/googlecode/jarjar/jarjar/1.3/jarjar-1.3.jar'
  open(url, 'rb') do |src|
    open('javalib/jarjar.jar', 'wb') do |dest|
      dest.write(src.read)
    end
  end
  open('javalib/rename-asm.jarjar', 'wb') do |dest|
    dest.write("rule org.objectweb.** mirah.objectweb.@1")
  end
end

def build_jar(new_jar, build_dir)
  # Build the jar
  ant.jar 'jarfile' => new_jar do
    fileset 'dir' => build_dir, 'excludes' => 'META-INF/*'
    zipfileset 'src' => 'javalib/mirah-asm-5.jar', 'includes' => 'mirah/objectweb/**/*'
    zipfileset 'src' => 'javalib/mirah-parser.jar'
    metainf 'dir' => File.dirname(__FILE__), 'includes' => 'LICENSE,COPYING,NOTICE'
    metainf 'dir' => build_dir, 'includes' => 'META-INF/*'
    manifest do
      attribute 'name' => 'Main-Class', 'value' => 'org.mirah.MirahCommand'
    end
  end
end

desc "create version file from ENV MIRAH_MAJOR_VERSION, MIRAH_MINOR_VERSION"
task :mirah_version => "build/generated/"
file "build/generated/"  do
  major=ENV["MIRAH_VERSION_MAJOR"] || "0.1.5"
  minor=ENV["MIRAH_VERSION_MINOR"] || "dev"

  genpath = "build/generated/org/mirah"
  mkdir_p genpath
  File.open("#{genpath}/Version.mirah", 'w') do |dest|
       dest.write("package org.mirah
class Version
   attr_reader minor:String
   attr_reader major:String
   VERSION = Version.new('#{major}', '#{minor}')

   private def initialize(major:String, minor:String)
     @major = major
     @minor = minor
     @str =  major +'-'+ minor
   end

   def toString
     @str
   end
  end
")
    end
end


def bootstrap_mirah_from(old_jar, new_jar, options={})
  optargs = options[:optargs] ||[]
  mirah_srcs = Dir['build/generated/'] +
      Dir['src/org/mirah/*.mirah'].sort +
      Dir['src/org/mirah/jvm/types/'] +
      Dir['src/org/mirah/{macros,util}/'] +
      Dir['src/org/mirah/typer/'] +
      Dir['src/org/mirah/jvm/{compiler,mirrors,model}/'] +
      Dir['src/org/mirah/tool/'] +
      Dir['src/org/mirah/plugin/*.mirah'].sort

  extensions_srcs = Dir['src/org/mirah/builtins/']

  plugin_srcs = Dir['src/org/mirah/plugin/impl/']

  ant_srcs        =    ['src/org/mirah/ant/compile.mirah']

  file new_jar, [:verbose] => mirah_srcs + extensions_srcs + ant_srcs + [old_jar, 'javalib/mirah-asm-5.jar', 'javalib/mirah-parser.jar'] + [:mirah_version] do |task, task_args|
    task_args.with_defaults(:verbose => false)
    build_dir = 'build/bootstrap'+new_jar.gsub(/[.-\/]/, '_')
    cp "#{new_jar}", "#{new_jar}.prev" rescue nil
    rm_rf build_dir
    mkdir_p build_dir
    mkdir_p "#{build_dir}/META-INF/services"

    # Compile Java sources
    ant.javac 'source' => '1.6',
              'target' => '1.6',
              'destdir' => build_dir,
              'srcdir' => 'src',
              'includeantruntime' => false,
              'debug' => true,
              'listfiles' => true

    # mirahc needs to be 1.7 or lower

    ant_classpath = $CLASSPATH.grep(/ant/).map{|x| x.sub(/^file:/,'')}.join(File::PATH_SEPARATOR)
    default_class_path = [ "javalib/mirah-parser.jar", "javalib/mirah-asm-5.jar", build_dir].join(File::PATH_SEPARATOR)
    build_class_path = ["javalib/mirah-parser.jar", "javalib/mirah-asm-5.jar", build_dir].join(File::PATH_SEPARATOR)

    # process all sources with old_jar
    build_class_path = options[:use_old_jar] ? old_jar : build_class_path

    optargs += ['--jvm', build_version, '-d', build_dir]

    report = Measure.measure do |x|
      x.report "Compile Mirah core" do
        args = task_args[:verbose] == 'true' ? ['-V'] : []
        args += ['-classpath', default_class_path]
        run_mirahc("core-#{old_jar}", old_jar, *(args + optargs + mirah_srcs))
      end

      x.report "compile ant stuff" do
        args = ['-classpath', [build_class_path,ant_classpath].join(File::PATH_SEPARATOR)]
        ant_sources = ['src/org/mirah/ant']
        run_mirahc("ant-#{old_jar}", build_class_path, *(args + optargs + ant_sources))
      end

      x.report "compile extensions" do
        args = task_args[:verbose] == 'true' ? ['-V'] : []
        args += [ '-classpath', build_class_path ]
        run_mirahc("ext-#{old_jar}", build_class_path, *(args + optargs + extensions_srcs))
        cp_r 'src/org/mirah/builtins/services', "#{build_dir}/META-INF"
      end

      x.report "compile plugins" do
        args = task_args[:verbose] == 'true' ? ['-V'] : []
        args += [ '-classpath', build_class_path]
        run_mirahc("plugins-#{old_jar}", build_class_path, *(args + optargs + plugin_srcs))
        cp_r 'src/org/mirah/plugin/impl/services', "#{build_dir}/META-INF"
      end

      x.report "build jar" do
        build_jar(new_jar, build_dir)
      end
    end

    report.print
    rm_f "#{new_jar}.prev"
  end
end

bootstrap_mirah_from('javalib/mirahc-prev.jar', 'dist/mirahc.jar')
bootstrap_mirah_from('dist/mirahc.jar', 'dist/mirahc2.jar')
bootstrap_mirah_from('dist/mirahc2.jar', 'dist/mirahc3.jar')
bootstrap_mirah_from('dist/mirahc.jar', 'dist/mirahc-stub.jar', {:optargs => ['-skip-compile','-plugins', 'stub:+pl'], :use_old_jar => true})


def build_version
  build_version = java.lang.System.getProperty('java.specification.version')
  if build_version.to_f > 1.7
    build_version = '1.7'
  end
  build_version
end

def run_java(*args)
  sh 'java', *args
  unless $?.success?
    exit $?.exitstatus
  end
end

def run_jar(jar, *args)
  run_java '-jar', jar, *args
end

def run_mirahc(step, mirahc_jar, *args)
  file_name = step.gsub /[\/\\]/, '_'
  run_java '-Xms712m', '-Xmx712m', '-XX:+PrintGC','-XX:+PrintGCDetails','-XX:+PrintGCDateStamps',"-Xloggc:build/#{file_name}_gc.log", '-cp', mirahc_jar, 'org.mirah.MirahCommand', *args
end

class Measure

  def initialize
    @measures =[]
  end

  def self.measure
    report = Measure.new
    yield report
    return report
  end

  def report name
    start = Time.now
    yield self
    @measures << [name, Time.now - start]
  end

  def print
    total = 0
    @measures.each do |m|
      total += m[1]
      puts "#{m.join ': '}sec"
    end
    puts "Total time: #{total}sec"
  end
end
