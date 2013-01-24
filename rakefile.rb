include FileTest

# Build configuration
load "VERSION.txt"

CONFIG = ENV["config"] || "Release"
PLATFORM = ENV["platform"] || "x86"
BUILD_NUMBER = "#{BUILD_VERSION}.#{(ENV["BUILD_NUMBER"] || Time.new.strftime('5%H%M'))}"
MONO = (RUBY_PLATFORM.downcase.include?('linux') or RUBY_PLATFORM.downcase.include?('darwin'))
TEAMCITY = !ENV["BUILD_NUMBER"].nil?

# Paths
BASE_PATH = File.expand_path(File.dirname(__FILE__))
SOURCE_PATH = "#{BASE_PATH}/src"
TESTS_PATH = "#{BASE_PATH}/src"
SPECS_PATH = "#{BASE_PATH}/specs"
BUILD_PATH = "#{BASE_PATH}/build"
RESULTS_PATH = "#{BUILD_PATH}/results"
ARTIFACTS_PATH = "#{BASE_PATH}/artifacts"
NUSPEC_PATH = "#{BASE_PATH}/packaging/nuget"
NUGET_PATH = "#{BUILD_PATH}/nuget"
TOOLS_PATH = "#{BASE_PATH}/tools"

# Files
ASSEMBLY_INFO = "#{SOURCE_PATH}/CommonAssemblyInfo.cs"
SOLUTION_FILE = "#{SOURCE_PATH}/Simple.Web.sln"
VERSION_INFO = "#{BASE_PATH}/VERSION.txt"

# Matching
TEST_ASSEMBLY_PATTERN_PREFIX = ".Tests"
TEST_ASSEMBLY_PATTERN_UNIT = "#{TEST_ASSEMBLY_PATTERN_PREFIX}.Unit"
TEST_ASSEMBLY_PATTERN_INTEGRATION = "#{TEST_ASSEMBLY_PATTERN_PREFIX}.Integration"
SPEC_ASSEMBLY_PATTERN = ".Specs"

# Set up our build system
require 'albacore'
require 'rake/clean'
require 'pathname'

XUNIT_COMMAND = "#{TOOLS_PATH}/xUnit/xunit.console.clr4.#{(PLATFORM.empty? or PLATFORM.eql?('x86') ? 'x86' : '')}.exe"
MSPEC_COMMAND = "#{TOOLS_PATH}/mspec/mspec.exe"

# Configure albacore
Albacore.configure do |config|
    config.log_level = (TEAMCITY ? :verbose : :normal)

    config.msbuild.solution = SOLUTION_FILE
    config.msbuild.properties = { :configuration => CONFIG }
    config.msbuild.use :net4
    config.msbuild.targets = [ :Clean, :Build ]
    config.msbuild.verbosity = "normal"

    config.xbuild.solution = SOLUTION_FILE
    config.xbuild.properties = { :configuration => CONFIG, :vstoolspath => (RUBY_PLATFORM.downcase.include?('darwin') ? '/Library/Frameworks/Mono.framework/Libraries' : '/usr/lib') + '/mono/xbuild/Microsoft/VisualStudio/v9.0' }
    config.xbuild.targets = [ :Build ] #:Clean upsets xbuild
    config.xbuild.verbosity = "normal"

    config.mspec.command = (MONO ? 'mono' : XUNIT_COMMAND)
    config.mspec.assemblies = FileList.new("#{SPECS_PATH}/**/*#{SPEC_ASSEMBLY_PATTERN}.dll").exclude(/obj\//).collect! { |element| ((MONO ? "#{MSPEC_COMMAND} " : '') + element) }

    CLEAN.include(FileList["#{SOURCE_PATH}/**/obj"])
	CLOBBER.include(FileList["#{SOURCE_PATH}/**/bin"])
	CLOBBER.include(BUILD_PATH)
end

# Tasks
task :default => [:test]

desc "Build"
task :build => [:init, :assemblyinfo] do
	if MONO
		Rake::Task[:xbuild].invoke
	else
		Rake::Task[:msbuild].invoke
	end
end

desc "Build + Tests (default)"
task :test => [:build] do
	Rake::Task[:runtests].invoke(TEST_ASSEMBLY_PATTERN_PREFIX)
end

desc "Build + Unit tests"
task :quick => [:build] do
	Rake::Task[:runtests].invoke(TEST_ASSEMBLY_PATTERN_UNIT)
end

desc "Build + Tests + Specs"
task :full => [:test] #[:test, :mspec]

# Hidden tasks
task :init => [:clobber] do
	Dir.mkdir BUILD_PATH unless File.exists?(BUILD_PATH)
	Dir.mkdir RESULTS_PATH unless File.exists?(RESULTS_PATH)
	Dir.mkdir ARTIFACTS_PATH unless File.exists?(ARTIFACTS_PATH)
end

task :ci => [:full]

msbuild :msbuild

xbuild :xbuild

assemblyinfo :assemblyinfo do |asm|
	asm_version = BUILD_NUMBER

	begin
		commit = `git log -1 --pretty=format:%H`
	rescue
		commit = "git unavailable"
	end

	asm.language = "C#"
	asm.version = BUILD_NUMBER
	asm.file_version = BUILD_NUMBER
	asm.company_name = "Mark Rendle"
	asm.product_name = "Simple.Web"
	asm.copyright = "Copyright (C) Mark Rendle 2012"
	asm.custom_attributes :AssemblyConfiguration => CONFIG, :AssemblyInformationalVersion => asm_version
	asm.output_file = ASSEMBLY_INFO
	asm.com_visible = false
end

task :runtests, [:boundary] do |t, args|
	args.with_default(:boundary => "*")
	
	runner = XUnitTestRunner.new(MONO ? 'mono' : XUNIT_COMMAND)
	runner.html_output = RESULTS_PATH

	assemblies = Array.new

	args["boundary"].split(/,/).each do |this_boundary|
		FileList.new("#{TESTS_PATH}/*#{this_boundary}")
				.collect! { |element| 
					FileList.new("#{element}/**/*#{this_boundary}.dll")
						.exclude(/obj\//)
						.each do |this_file|
							assemblies.push (MONO ? "#{XUNIT_COMMAND} " : '') + this_file
						end
				}

		runner.assemblies = assemblies
		runner.execute
	end
end

mspec :mspec