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

class EnumTest < Test::Unit::TestCase

  def test_enum_functions
    cls, = compile_no_warnings(<<-EOF)
      enum TestEnumF
        A, B, C
      end
      puts TestEnumF.values.size == 3
      puts TestEnumF.valueOf('A') === TestEnumF.A
      puts TestEnumF.C.ordinal == 2
      puts TestEnumF.B.name == 'B'
     EOF
     assert_run_output("true\ntrue\ntrue\ntrue\n", cls)
  end

  def test_enum_constructors
    cls, = compile_no_warnings('
      enum TestEnumC
        A, B(:b), C(TestEnumC.B.name)
        def initialize
          @x = :a
        end
        def initialize(s:String)
          @x = s
        end
        def toString; "#{name}#{@x}"; end
      end
      puts TestEnumC.A
      puts TestEnumC.B.toString
      puts ""+TestEnumC.C
     ')
     assert_run_output("Aa\nBb\nCB\n", cls)
  end

  def test_enum_inheritance
    cls, = compile_no_warnings('
      enum TestEnumD
        A,
        B {
          def foo
            :justB
          end
        },
        C(TestEnumD.B.name) {
          def foo
            x = super
            x + "andC"
          end
        }
        def initialize
          @x = :a
        end
        def initialize(s:String)
          @x = s
        end
        def foo
          toString
        end
        def toString
          "#{name}#{@x}"
        end
      end
      puts TestEnumD.A.foo
      puts TestEnumD.B.foo
      puts TestEnumD.C.foo
    ')
    assert_run_output("Aa\njustB\nCBandC\n", cls)
  end

  def test_enum_in_case
    cls, = compile_no_warnings('
      x = TestEnumE.A
      case x
        when TestEnumE.B then puts x
        when TestEnumE.A then puts x
      end
      enum TestEnumE
        A, B, C
      end
    ')
    assert_run_output("A\n", cls)
  end
end
