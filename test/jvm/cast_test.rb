# Copyright (c) 2013 The Mirah project authors. All Rights Reserved.
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

class CastTest < Test::Unit::TestCase

  def test_cast
    cls, = compile(<<-EOF)
      def f2b; (1.0):byte; end
      def f2s; (1.0):short; end
      def f2c; (1.0):char; end
      def f2i; (1.0):int; end
      def f2l; (1.0):long; end
      def f2d; (1.0):int; end

      def i2b; (1):byte; end
      def i2s; (1):short; end
      def i2c; (1):char; end
      def i2l; (1):long; end
      def i2f; (1):float; end
      def i2d; (1):int; end

      def b2s; ((1):byte):short; end
      def b2c; ((1):byte):char; end
      def b2i; ((1):byte):int; end
      def b2l; ((1):byte):long; end
      def b2f; ((1):byte):float; end
      def b2d; ((1):byte):double; end

      def s2b; ((1):short):byte; end
      def s2c; ((1):short):char; end
      def s2i; ((1):short):int; end
      def s2l; ((1):short):long; end
      def s2f; ((1):short):float; end
      def s2d; ((1):short):double; end

      def c2b; ((1):char):byte; end
      def c2s; ((1):char):short; end
      def c2i; ((1):char):int; end
      def c2l; ((1):char):long; end
      def c2f; ((1):char):float; end
      def c2d; ((1):char):double; end

      def l2b; ((1):long):byte; end
      def l2c; ((1):long):char; end
      def l2i; ((1):long):int; end
      def l2l; ((1):long):long; end
      def l2f; ((1):long):float; end
      def l2d; ((1):long):double; end

      def d2b; (1.0):byte; end
      def d2s; (1.0):short; end
      def d2c; (1.0):char; end
      def d2i; (1.0):int; end
      def d2l; (1.0):long; end
      def d2f; (1.0):float; end

      def hard_i2f(a:int)
        if a < 0
          a *= -1
          a * 2
        else
          a * 2
        end:float
      end
    EOF

    assert_equal 1, cls.b2s
    assert_equal 1, cls.b2c
    assert_equal 1, cls.b2i
    assert_equal 1, cls.b2l
    assert_equal 1.0, cls.b2f
    assert_equal 1.0, cls.b2d

    assert_equal 1, cls.s2b
    assert_equal 1, cls.s2c
    assert_equal 1, cls.s2i
    assert_equal 1, cls.s2l
    assert_equal 1.0, cls.s2f
    assert_equal 1.0, cls.s2d

    assert_equal 1, cls.c2b
    assert_equal 1, cls.c2s
    assert_equal 1, cls.c2i
    assert_equal 1, cls.c2l
    assert_equal 1.0, cls.c2f
    assert_equal 1.0, cls.c2d

    assert_equal 1, cls.i2b
    assert_equal 1, cls.i2s
    assert_equal 1, cls.i2c
    assert_equal 1, cls.i2l
    assert_equal 1.0, cls.i2f
    assert_equal 1.0, cls.i2d

    assert_equal 1, cls.f2b
    assert_equal 1, cls.f2s
    assert_equal 1, cls.f2c
    assert_equal 1, cls.f2i
    assert_equal 1, cls.f2l
    assert_equal 1.0, cls.f2d

    assert_equal 1, cls.d2b
    assert_equal 1, cls.d2s
    assert_equal 1, cls.d2c
    assert_equal 1, cls.d2i
    assert_equal 1, cls.d2l
    assert_equal 1.0, cls.d2f

    assert_equal 2.0, cls.hard_i2f(1)
    assert_equal 4.0, cls.hard_i2f(-2)
  end

  def test_java_lang_cast
    cls, = compile(<<-EOF)
      def foo(a:Object)
        a:Integer.intValue
      end
    EOF

    assert_equal(2, cls.foo(java.lang.Integer.new(2)))
  end

  def test_array_cast
    cls, = compile(<<-EOF)
      def foo(a:Object)
        bar(String[].cast(a))
      end

      def bar(a:String[])
        a[0]
      end
    EOF

    assert_equal("foo", cls.foo(["foo", "bar"].to_java(:string)))
  end

  def test_array_cast_primitive
    cls, = compile(<<-EOF)
      def foo(a:Object)
        bar(int[].cast(a))
      end

      def bar(a:int[])
        a[0]
      end
    EOF

    assert_equal(2, cls.foo([2, 3].to_java(:int)))
  end
  
  def test_explicit_block_argument_cast_in_array_iteration
     cls, = compile(<<-EOF)
      def foo():int
        list = [1,2,3]
        m = 0
        list.each do |x: int|
          m += x
        end
        return m
      end
    EOF
    assert_equal 6, cls.foo
  end
  
  def test_explicit_call_cast_in_array_iteration
     cls, = compile(<<-EOF)
      def foo():int
        list = [1,2,3]
        m = 0
        list.each do |x|
          m = x:int + m
        end
        return m
      end
    EOF
    assert_equal 6, cls.foo
  end

  def test_cast_array_and_assign
    cls, = compile(<<-EOF)
      def foo():Object
        [1,2,3].toArray(Integer[3])
      end
      def bar:int
        a = foo:Integer[][0]
        foo:Integer[][1] + a
      end
    EOF
    assert_equal 3, cls.bar
  end

  def test_chained_casts
    cls, = compile(<<-EOF)
      def foo():Object
        [1,2,3].toArray(Integer[3])
      end

      def bar:Number
        foo:Object[][2]:Integer.intValue:Number
      end
    EOF
    assert_equal 3, cls.bar
  end

  def test_lhs_type_hint
    cls, = compile(<<-EOF)
    class LhsTest
      CONST:Integer = 1:Number
      def foo():Object
        [1,2,3].toArray(Integer[3])
      end
      def bar:int
        @a:Integer[] = foo
        b:int = @a[0]
        b + @a[1] + CONST
      end
    end
    EOF
    assert_equal 4, cls.new.bar
  end

  def test_implisit_unboxing_array_iteration
     cls, = compile(<<-EOF)
      def foo():int
		list = [1,2,3]
		m = 0
		list.each do |x:int|
			m += x
		end
		return m
      end
    EOF
	assert_equal(6, cls.foo())
  end

  def test_explisit_unboxing_array_iteration
     cls, = compile(<<-EOF)
      def foo():int
		list = [1,2,3]
		m = 0
		list.each do |x|
			m = x:int + m
		end
		return m
      end
    EOF
	assert_equal(6, cls.foo())
  end

  def test_no_errors_for_interface_casts
    cls, = compile(<<-EOF)
      a = nil:Runnable
      b:java::io::Serializable = nil
      a = b:Runnable
      c = Number.new
      a = c:Runnable
      c = b:Number
    EOF
  rescue Exception => ex
    fail "casts for interfaces #{ex} #{ex.backtrace.join "\n"}"
  end

  def test_unboxing_for_object
    cls, = compile(<<-EOF)
      def bar:Object
        6:Integer
      end
      def foo:int
        return bar:int
      end
    EOF
    assert_equal(6, cls.foo())
  end

end
