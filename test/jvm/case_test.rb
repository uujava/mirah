# Copyright (c) 2015 The Mirah project authors. All Rights Reserved.
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

class CaseTest < Test::Unit::TestCase
  java_import 'java.util.Locale'

  def test_simple_case_when_first
    cls, = compile_no_warnings(<<-EOF)
      puts(case
        when 1 == 1
          1
        when 1 == 2
          0
      end)
     EOF
     assert_run_output("1\n", cls)
  end

  def test_simple_case_else
    cls, = compile_no_warnings(<<-EOF)
      puts(case
        when 1 == 2
          1
        else
          2
      end)
     EOF
     assert_run_output("2\n", cls)
  end
  def test_simple_case_when
    cls, = compile_no_warnings(<<-EOF)
      puts(case
        when 1 == 1
          3
        else
          2
      end)
     EOF
     assert_run_output("3\n", cls)
  end

  def test_simple_case_when_when_assignment
    cls, = compile_no_warnings(<<-EOF)
      x = case
        when 1 == 2; 1
        when 1 == 1; 3
        else 2
      end
      puts x
     EOF
     assert_run_output("3\n", cls)
  end

  def test_simple_case_multiple_conditions
    cls, = compile_no_warnings(<<-EOF)
      puts(case
        when 1 == 2 then 1
        when 1 == 3, 1==1 then 3
        else 2
      end)
    EOF
    assert_run_output("3\n", cls)
  end

  def test_simple_case_void_expression
    cls, = compile_no_warnings(<<-EOF)
      case
        when 1 == 1 then puts 1
        else puts 2
      end
      case
        when 1 == 2 then puts 1
        else puts 2
      end
    EOF
    assert_run_output("1\n2\n", cls)
  end

  def test_equals_case
    cls, = compile_no_warnings(<<-EOF)
      a = Object.new
      case a
        when a then puts 1
        else puts 2
      end
    EOF
    assert_run_output("1\n", cls)
  end

  def test_equals_case_default_and_expression
    cls, = compile_no_warnings(<<-EOF)
      x = case Object.new
        when Object.new then 1
        else 2
      end
      puts x
    EOF
    assert_run_output("2\n", cls)
  end

  def test_equals_case_nil
    cls, = compile_no_warnings(<<-EOF)
      case nil
        when Object.new then puts 1
        else puts 2
      end
    EOF
    assert_run_output("2\n", cls)
  end

  def test_equals_case_nil_nil
    cls, = compile_no_warnings(<<-EOF)
      case nil
        when nil then puts 1
        else puts 2
      end
    EOF
    assert_run_output("2\n", cls)
  end

  def test_equals_multiple_when
    cls, = compile_no_warnings(<<-EOF)
      a = Object.new
      puts(case a
        when Object.new then 1
        when Object.new, a then 3
        else 2
      end)
    EOF
    assert_run_output("3\n", cls)
  end

  def test_equals_multiple_fit_but_first_win
    cls, = compile_with_warnings(<<-EOF, ['incompatible with table switch condition type: java.lang.Integer'])
      a = 1:Integer
      puts(case a
        when Integer.new(1) then 1
        when Object.new, a then 3
        when true:Boolean then 4
        else 2
      end)
    EOF
    assert_run_output("1\n", cls)
  end

  def test_equals_and_boxing
    cls, = compile_with_warnings(<<-EOF)
      a = 1
      case a
        when Integer.new(1) then puts 1
        else puts 2
      end
    EOF
    assert_run_output("1\n", cls)
  end

  def test_equals_and_different_result
    cls, = compile_with_warnings(<<-EOF)
      x = case 1
        when Integer.new(1) then 1:Long
        else 2:Integer
      end
      puts x.getClass
      x = case 2
        when Integer.new(1) then 1:Long
        else 2:Integer
      end
      puts x.getClass
    EOF
    assert_run_output("class java.lang.Long\nclass java.lang.Integer\n", cls)
  end

  def test_equals_and_boxing_result
    code = <<-EOF
      x = case 1
        when Integer.new(1) then 1:Integer
        else 2
      end
      puts x
      x = case 2
        when Integer.new(1) then 1:long
        else 2:Long
      end
      puts x
    EOF

    cls, = compile_with_warnings(code, ['incompatible with table switch condition type: int', 'does not support switch' ])
    assert_run_output("1\n2\n", cls)

  end

  def test_simplest_int_switch
    code = <<-EOF
      x = case 1
        when 1 then 1
        else 2
      end
      puts x
      x = case 2
        when 1 then 1:long
        else 2:Long
      end
      puts x
    EOF

    cls, = compile_no_warnings(code)
    assert_run_output("1\n2\n", cls)

  end

  def test_int_switch_with_constants
    code = <<-EOF
      class test_int_switch_with_constants
        C = 1
        def self.foo
          a = C
          case a
            when Integer.MAX_VALUE then puts 0
            when Integer.MIN_VALUE then puts -1
            when C then puts 1
            when test_int_switch_with_constants_const::C then puts 3
            else puts 2
          end
        end
      end
      class test_int_switch_with_constants_const
        C = 3
      end

       test_int_switch_with_constants.foo
    EOF
    cls, = compile_no_warnings(code)
    assert_run_output("1\n", cls)
  end

  def test_int_switch_local_initialized
    code = <<-EOF
      x = case 1
        when Integer.MAX_VALUE then 2
      end
      # local initialized to 0 by default
      puts x
    EOF
    cls, = compile_no_warnings(code)
    assert_run_output("0\n", cls)
  end

  def test_int_switch_local_assign_in_body
    code = <<-EOF
      y = case 1
        when 2 then x = 2
        else x = 1
      end
      # local initialized to 0 by default
      puts x
      puts y
      puts x==y
    EOF
    cls, = compile_no_warnings(code)
    assert_run_output("1\n1\ntrue\n", cls)
  end

  def test_int_switch_unbox_condition
    code = <<-EOF
      puts(case 1:Integer
       when 1; 1
       else 2
      end)
    EOF
    cls, = compile_no_warnings(code)
    assert_run_output("1\n", cls)
  end

  def test_int_switch_convert_body
    code = <<-EOF
       x = case 1
         when Integer.MAX_VALUE then 0
         when 1 then 1:Integer
         else 2:Short
       end
      puts x.getClass.getName
    EOF
    cls, = compile_no_warnings(code)
    assert_run_output("java.lang.Integer\n", cls)
  end

  def test_int_switch_on_character
    code = <<-EOF
      case 97:char
        when ?a then puts 97:char
        else puts 2
      end
    EOF
    cls, = compile_no_warnings(code)
    assert_run_output("a\n", cls)
  end

  def test_string_switch
    code = <<-EOF
      class TestStringSwitch
        A = "x"
        B = "b"
        def self.foo
          a = "abc"
          x = case a
            when TestStringSwitchConst::A then 0
            when A then (-1)
            else 2
          end
          puts x
          x = case "vvv"
            when TestStringSwitchConst::A then 0
            when A then (-1)
            else 2
          end
          puts x
          x = case "b"
            when TestStringSwitchConst::A then 0
            when A, B then (-1)
            else 2
          end
          puts x
          case "b"
            when TestStringSwitchConst::A then puts 0
            when A, B then puts -1
            else puts 2
          end
        end
      end
      class TestStringSwitchConst
        A = "abc"
      end
      TestStringSwitch.foo
    EOF
    cls, = compile_no_warnings(code)
    assert_run_output("0\n2\n-1\n-1\n", cls)
  end

  def test_string_same_hash_warning
    code = <<-EOF
      class TestStringSwitchHash
        def self.foo
          case 'c'
            when 'FB' then puts 0
            when 'Ea' then puts 1
            else  puts 2
          end
        end
      end
      TestStringSwitchHash.foo
    EOF
    cls, = compile_with_warnings(code, ['same hash'])
    assert_run_output("2\n", cls)
  end

  def test_enum_switch
    code = <<-EOF
      import java.nio.file.AccessMode
      a = AccessMode.READ
      case a
       when AccessMode.WRITE then puts 1
       when AccessMode.READ then puts 2
       else puts 3
      end
    EOF
    cls, = compile_no_warnings(code)
    assert_run_output("2\n", cls)
  end
  def test_return_case
    code = <<-EOF
      import java.nio.file.AccessMode
      class TestReturnCase
        def self.ret_case
          return case AccessMode.EXECUTE
            when AccessMode.WRITE then 1
            when AccessMode.READ then 2
            else 3
          end
        end
      end
      puts TestReturnCase.ret_case
    EOF
    cls, = compile_no_warnings(code)
    assert_run_output("3\n", cls)
  end

  def compile_with_warnings(code, warnings = nil)
    diag_hash = {}
    classes = compile(code) { |diag| add_diag(diag_hash, diag) }
    raise "Found errors #{diag_hash[:error]}" if diag_hash[:error]
    raise "No warinings" unless diag_hash[:warn]
    if warnings
      contains = []
      warnings.each do |message|
        diag_hash[:warn].each do |warn|
          contains += warn.scan(message)
        end
      end
      diff = warnings - contains
      raise "Missing warnings: #{diff}" unless diff.empty?
    end
    classes
  end

  def compile_no_warnings(code)
    diag_hash = {}
    classes = compile(code) { |diag| add_diag(diag_hash, diag) }
    raise "Found errors #{diag_hash[:error]}" if diag_hash[:error]
    raise "Warnings found #{diag_hash[:warn]}" if diag_hash[:warn]
    classes
  end

  def add_diag(hash, diagnostic)
    if diagnostic.kind.name == "ERROR"
      (hash[:error] ||=[]) << diagnostic.getMessage(Locale.getDefault)
    end
    if diagnostic.kind.name == "WARNING"
      (hash[:warn] ||=[]) << diagnostic.getMessage(Locale.getDefault)
    end
  end
end
