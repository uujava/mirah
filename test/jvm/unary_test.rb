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

class UnaryTest < Test::Unit::TestCase

  def test_unary_to_local
    cls, = compile(<<-EOF)
      c = 0
      puts c -1
      puts c -1+2
    EOF
    assert_run_output("-1\n1\n", cls)
  end

  def test_unary_functional_call
    cls, = compile(<<-EOF)
      def c(i:int); puts i; end
      def d; 2; end
      c -1
      puts d -1
    EOF
    assert_run_output("-1\n1\n", cls)
  end

  def test_unary_call
    cls, = compile(<<-EOF)
      class X
        def c(i:int); puts i; end
        def d; 2; end
      end
      X.new.c -1
      puts X.new.d -1
      x = X.new
      x.c -x.d
      x.c -2+x.d
    EOF
    assert_run_output("-1\n1\n-2\n0\n", cls)
  end

  def test_multi_arg_call
    cls, = compile(<<-EOF)
      class X
        def c(i:int, j:int); puts i+j; end
        def d; 2; end
      end
      x = X.new
      x.c -1,2
      x.c(-1, 2)
      x.c -1,-2
      x.c 1,-2
      x.c -1*x.d, 2
      x.c -(-x.d - 2 + x.d), x.d
      x.c -1*x.d, +x.d
    EOF
    assert_run_output("1\n1\n-3\n-1\n0\n4\n0\n", cls)
  end
end
