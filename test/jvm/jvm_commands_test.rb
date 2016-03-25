# Copyright (c) 2010 The Mirah project authors. All Rights Reserved.
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
require 'test_helper'


class JVMCommandsTest < Test::Unit::TestCase

  def test_dash_e_eval
    assert_output "1\n" do
      Mirah.run('-e','puts 1')
    end
  end

  def test_dash_e_with_methods
    assert_output "1\n2\n" do
      Mirah.run('-e','
       def self.sprint(*args:Object):void
          args.each do|x|
            puts x
          end
       end

       def print(*args:Object):void
          sprint args
       end
       print 1,2
      ')
    end
  end

  def test_dash_e_with_macro
    assert_output "1\n" do
      Mirah.run('-e','
       macro def sprint(node):void
         quote { puts `node` }
       end

       sprint 1
      ')
    end
  end

  def test_dash_e_with_closure
    assert_output "1\n" do
      Mirah.run('-e','
       t = Thread.new {puts 1}
       t.start
       t.join
      ')
    end
  end

  def test_force_verbose_has_logging
    out = capture_output do
      Mirah.run('-V', '-e','puts 1')
    end
    assert out.include? "Finished class DashE"
  end

  def test_runtime_classpath_modifications
    assert_output "1234\n" do
      Mirah.run('-cp', FIXTURE_TEST_DEST,
                                '-e',
                                  'import org.foo.LowerCaseInnerClass
                                  puts LowerCaseInnerClass.inner.field'
                              )
    end
  end

  def test_dash_c_is_deprecated
    assert_output "WARN: option -c is deprecated.\n1234\n" do
      Mirah.run('-c', FIXTURE_TEST_DEST,
                                '-e',
                                  'import org.foo.LowerCaseInnerClass
                                  puts LowerCaseInnerClass.inner.field'
                              )
    end
  end

  def test_encoding
    assert_output "default utf8 encoding test\n" do
      Mirah.run(File.dirname(__FILE__)+"/../fixtures/utf8_test.mirah")
    end
    assert_output "cp1251 encoding test\n" do
      Mirah.run('-encoding','cp1251', File.dirname(__FILE__)+"/../fixtures/cp1251_test.mirah")
    end
  end

  def test_stub_plugin
    target_dir = 'tmp_test/stub'
    fixture_dir = File.dirname(__FILE__)+'/../fixtures'
    Mirah.compile('-d', target_dir,  '-plugins', 'stub', fixture_dir + '/stub_plugin_test.mirah')
    generated = File.read target_dir + '/org/foo/AOne.java'
    expected = File.read fixture_dir + '/org/foo/AOne.java'
    assert_equal expected.gsub(/\r/, ''), generated.gsub(/\r/, '')
    generated = File.read target_dir + '/org/foo/AOneX.java'
    expected = File.read fixture_dir + '/org/foo/AOneX.java'
    assert_equal expected.gsub(/\r/, ''), generated.gsub(/\r/, '')
  end
end
