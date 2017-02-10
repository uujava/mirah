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

class BlocksTest < Test::Unit::TestCase

  def parse_and_type code, name=tmp_script_name
    parse_and_resolve_types name, code
  end

  # this should probably be a core test
  def test_empty_block_parses_and_types_without_error
    assert_nothing_raised do
      parse_and_type(<<-CODE)
        interface Bar do;def run:void;end;end

        class BarOner
          def initialize; end
          def foo(a:Bar)
            1
          end
        end
        BarOner.new.foo do
        end
      CODE
    end
  end

  def test_non_empty_block_parses_and_types_without_error
    assert_nothing_raised do
      parse_and_type(<<-CODE)
        interface Bar
          def run:void; end
        end

        class NotEmptyAccepter
          def initialize; end
          def foo(a: Bar)
            1
          end
        end
        NotEmptyAccepter.new.foo do
          1
        end
      CODE
    end
  end

  def test_simple_block
    cls, = compile(<<-EOF)
      thread = Thread.new do
        puts "Hello"
      end
      begin
        thread.run
        thread.join
      rescue
        puts "Uh Oh!"
      end
    EOF
    assert_run_output("Hello\n", cls)
  end

  def test_arg_types_inferred_from_interface
    script, cls = compile(<<-EOF)
      import java.util.Observable
      class MyObservable < Observable
        def initialize
          setChanged
        end
      end

      o = MyObservable.new
      o.addObserver {|x, a| puts a}
      o.notifyObservers("Hello Observer")
    EOF
    assert_run_output("Hello Observer\n", script)
  end

  def test_closure
    cls, = compile(<<-EOF)
      def foo
        a = "Hello"
        thread = Thread.new do
          puts a
        end
        begin
          a = a + " Closures"
          thread.run
          thread.join
        rescue
          puts "Uh Oh!"
        end
        return
      end
    EOF
    assert_output("Hello Closures\n") do
      cls.foo
    end
  end

  def test_int_closure
    cls, = compile(<<-EOF)
      def run(x:Runnable)
        x.run
      end
      def foo
        a = 1
        run {a += 1}
        a
      end
    EOF
    assert_equal(2, cls.foo)
  end


  def test_int_closure_with_int_as_method_param
    cls, = compile(<<-EOF)
      def run(x:Runnable)
        x.run
      end
      def foo a: int
        run { a += 1 }
        a
      end
    EOF
    assert_equal(2, cls.foo(1))
  end

  def test_block_with_method_def
    cls, = compile(<<-EOF)
      import java.util.ArrayList
      import java.util.Collections
      list = ArrayList.new(["a", "ABC", "Cats", "b"])
      Collections.sort(list) do
        def equals(a:Object, b:Object)
          a:String.equalsIgnoreCase(b:String)
        end
        def compare(a:Object, b:Object)
          a:String.compareToIgnoreCase(b:String)
        end
      end
      list.each {|x| puts x }
    EOF

    assert_run_output("a\nABC\nb\nCats\n", cls)
  end

  def test_block_with_abstract_from_object
    # Comparator interface also defines equals(Object) as abstract,
    # but it can be inherited from Object. We test that here.
    cls, = compile(<<-EOF)
      import java.util.Collections
      import java.util.List
      def sort(l:List)
        Collections.sort(l) do |a:Object, b:Object|
          a:String.compareToIgnoreCase(b:String)
        end
        l
      end
    EOF

    assert_equal(["a", "ABC", "b", "Cats"], cls.sort(["a", "ABC", "Cats", "b"]))
  end

  def test_block_with_no_arguments_and_return_value
    cls, = compile(<<-EOF)
      import java.util.concurrent.Callable
      def foo c:Callable
        # throws Exception
         puts c.call
      end
      begin
      foo do
        "an object"
      end
      rescue
        puts "never get here"
      end
    EOF
    assert_run_output("an object\n", cls)
  end

  def test_nesting_with_abstract_class
    # pend 'test_nesting_with_abstract_class' do
      cls, main = compile(%q{
      abstract class Nestable
        abstract def foo(n: Nestable):void;end
        def create(n: Nestable):void
           puts "create #{n}"
           n.foo(n)
        end

        def toString:String
           "nestable"
        end
      end

      class Main
        def self.create(b: Nestable):void
          b.foo(b)
        end

        def self.main(args: String[]):void
          create do |x:Nestable|
            puts "outer foo"
            create do |m: Nestable|
              puts "in foo #{m}"
              create do |m: Nestable|
                puts "deeper in foo #{m}"
              end
            end
            create do |m: Nestable|
              puts "in foo 1 #{m}"
            end
          end
        end
      end
})
      assert_output "outer foo\ncreate nestable\nin foo nestable\ncreate nestable\ndeeper in foo nestable\ncreate nestable\nin foo 1 nestable\n" do
        main.main([])
      end
    # end
  end

  def test_use_abstract_inplace
    cls, main, parent =  compile(%q{
    abstract class A < P

      def self.empty:A
        create do
          puts "empty"
        end
      end

      def self.create(n: A):A
         n
      end

    end

    class Main
      def self.create(b: P = A.empty):void
         puts "create #{b.class} #{b.getClass}"
         b.execute
      end

      def self.main(args: String[]):void
        create
        create { puts "not empty"}
      end
    end

    abstract class P
      abstract def execute:void;end
    end
})
    assert_output "create class P class A$empty$Closure2\nempty\ncreate class P class Main$main$Closure1\nnot empty\n" do
      main.main([])
    end
  end

  def test_parameter_used_in_block
    cls, = compile(<<-'EOF')
      def r(r:Runnable); r.run; end
      def foo(x: String): void
        r do
          puts "Hello #{x}"
        end
      end

      foo('there')
    EOF
    assert_run_output("Hello there\n", cls)
  end

  def test_block_with_mirah_interface
    cls, interface = compile(<<-EOF)
      interface MyProc do
        def call:void; end
      end
      def foo(b:MyProc)
        b.call
      end
      def bar
        foo {puts "Hi"}
      end
    EOF
    assert_output("Hi\n") do
      cls.bar
    end
  end

  def test_block_impling_interface_w_multiple_methods
   begin
      parse_and_type(<<-CODE)
        interface RunOrRun2 do
          def run:void;end
          def run2:void;end
        end

        class RunOrRun2Fooer
          def foo(a:RunOrRun2)
            1
          end
        end
        RunOrRun2Fooer.new.foo do
          1
        end
        CODE
    rescue => ex
      assert_match /multiple abstract/i, ex.message 
    else
      fail "No exception raised"
    end
  end

  def test_block_with_missing_params
    cls, = compile(<<-CODE)
        interface Bar do
          def run(a:String):void;end
        end

        class TakesABar
          def foo(a:Bar)
            a.run("x")
          end
        end
        TakesABar.new.foo do
          puts "hi"
        end
        CODE
    assert_run_output("hi\n", cls)
  end

  def test_block_with_too_many_params
    exception = assert_raises Mirah::MirahError do
      parse_and_type(<<-CODE)
        interface SingleArgMethod do
          def run(a:String):void;end
        end

        class ExpectsSingleArgMethod
          def foo(a:SingleArgMethod)
            1
          end
        end
        ExpectsSingleArgMethod.new.foo do |a, b|
          1
        end
        CODE
    end
    assert_equal 'Does not override a method from a supertype.',
                  exception.message
  end

  def test_block_with_too_many_params_with_type
    exception = assert_raises Mirah::MirahError do
      parse_and_type(<<-CODE)
        class ExpectsNoArgMethod
          def self.foo(a:Runnable)
            1
          end
        end
        ExpectsNoArgMethod.foo do |a:Object|
          1
        end
      CODE
    end
    assert exception.message.start_with? 'Internal error in compiler: class java.lang.VerifyError Abstract methods not implemented for not abstract'
  end

  def test_call_with_block_assigned_to_macro
    cls, = compile(<<-CODE)
        class S
          def initialize(run: Runnable)
            run.run
          end
          def toString
            "1"
          end
        end
        if true
          a = {}
          a["wut"]= b = S.new { puts "hey" }
          puts a
          puts b
        end
      CODE
    assert_run_output("hey\n{wut=1}\n1\n", cls)
  end

  def test_nested_closure_in_closure_doesnt_raise_error
    cls, = compile(<<-CODE)
        interface BarRunner do;def run:void;end;end

        class Nestable
          def foo(a:BarRunner)
            a.run
          end
        end
        Nestable.new.foo do
          puts "first closure"
          Nestable.new.foo do
            puts "second closure"
          end
        end
      CODE
    assert_run_output("first closure\nsecond closure\n", cls)
  end

  def test_nested_closure_with_var_from_outer_closure
    cls, = compile(<<-'CODE')
      interface BarRunner do;def run:void;end;end

      class Nestable
        def foo(a:BarRunner)
          a.run
        end
      end
      Nestable.new.foo do
        c = "closure"
        puts "first #{c}"
        Nestable.new.foo do
          puts "second #{c}"
        end
      end
    CODE
    assert_run_output("first closure\nsecond closure\n", cls)
  end

  def test_nested_closure_with_nested_closed_over_args
    cls, = compile(<<-'CODE')
      interface Jogger do;def jog(pace:int):void;end;end

      class Nestable
        def foo(pace: int, a: Jogger)
          a.jog(pace)
        end
      end
      Nestable.new.foo 10 do |pace|
        puts "first #{pace}"
        Nestable.new.foo 20 do |inner_pace|
          puts "second #{pace} #{inner_pace}"
        end
      end
    CODE
    assert_run_output("first 10\nsecond 10 20\n", cls)
  end

  def test_nested_closure_with_nested_closed_over_args2
    cls, = compile(%q[
      interface Jogger do;def jog(param:int):void;end;end
      
      class Nestable
        def operate(blub: int, a: Jogger):void
          a.jog(blub)
        end
      end
      
      class Bar
        def baz(foo:int):void
          puts "bazstart"
          Nestable.new.operate(10) do |arg1|
            puts "first #{arg1} #{foo}"
            Nestable.new.operate 20 do |inner_pace|
              puts "second #{arg1} #{inner_pace} #{foo}"
            end
            Nestable.new.operate 30 do |inner_pace2|
              puts "third #{arg1} #{inner_pace2}  #{foo}"
            end
          end
        end
      end
      
      Bar.new.baz(4)
    ])
    assert_run_output("bazstart\nfirst 10 4\nsecond 10 20 4\nthird 10 30  4\n", cls)
  end

  def test_two_closures_capture_different_variables
    cls, = compile(%q[
      interface Jogger do;def jog(param:int):void;end;end
      
      class Nestable
        def operate(blub: int, a: Jogger):void
          a.jog(blub)
        end
      end
      
      class Bar
        def baz(foo:int):void
          puts "bazstart"
          bar = 7
          Nestable.new.operate(40) do |arg1|
            puts bar
          end
          Nestable.new.operate(10) do |arg1|
            puts "first #{arg1} #{foo}"
          end
        end
      end
      
      Bar.new.baz(4)
    ])
    assert_run_output("bazstart\n7\nfirst 10 4\n", cls)
  end

  def test_uncastable_block_arg_type_fails
    error = assert_raises Mirah::MirahError do
      compile(<<-EOF)
        import java.io.OutputStream
        def foo x:OutputStream
          x.write 1:byte
        rescue
        end
        foo do |b:String|
          puts "writing"
        end
      EOF
    end
    assert_equal "Cannot cast java.lang.String to int.", error.message
  end

  def test_method_requiring_subclass_of_abstract_class_finds_abstract_method
    cls, = compile(<<-EOF)
      import java.io.OutputStream
      def foo x:OutputStream
        x.write 1:byte
      rescue
      end
      foo do |b:int|
        puts "writing"
      end
    EOF
    assert_run_output("writing\n", cls)
  end

  def test_block_with_interface_method_with_2_arguments_with_types
    cls, = compile(<<-EOF)
      interface DoubleArgMethod do
        def run(a: String, b: int):void;end
      end

      class ExpectsDoubleArgMethod
        def foo(a:DoubleArgMethod)
          a.run "hello", 1243
        end
      end
      ExpectsDoubleArgMethod.new.foo do |a: String, b: int|
        puts a
        puts b
      end
    EOF
    assert_run_output("hello\n1243\n", cls)
  end

  def test_block_with_interface_method_with_2_arguments_without_types
    cls, = compile(<<-EOF)
      interface DoubleArgMethod2 do
        def run(a: String, b: int):void;end
      end

      class ExpectsDoubleArgMethod2
        def foo(a:DoubleArgMethod2)
          a.run "hello", 1243
        end
      end
      ExpectsDoubleArgMethod2.new.foo do |a, b|
        puts a
        puts b
      end
    EOF
    assert_run_output("hello\n1243\n", cls)
  end

  def test_closures_with_static_imports
    cls, = compile(<<-EOF)
      def foo a:Runnable
        a.run
      end
      foo do
        x = [2,1]
        import static java.util.Collections.*
        sort x
        puts x
      end
    EOF
    assert_run_output("[1, 2]\n", cls)
  end


  def test_method_returning_init_call_with_closure
    cls, = compile(<<-EOF)
      class InitWithRunnable
        def initialize(a: Runnable)
          a.run
        end
        def finish
          "finish"
        end
      end
      class Huh
      def wut(i: InitWithRunnable)
        puts i.finish
      end
      def regular
        InitWithRunnable.new { puts "Closure!"; nil }
      end
    end
      Huh.new.wut(Huh.new.regular)
    EOF

    assert_run_output("Closure!\nfinish\n", cls)
  end


  def test_closure_with_or
    cls, = compile(<<-EOF)
    def r(run: java.lang.Runnable) run.run; end
    r { puts "a" || "b"}
    EOF

    assert_run_output("a\n", cls)
  end

  def test_closure_with_or_ii
    cls, = compile(<<-EOF)
    interface C; def c(): String;end;end
    def r(cee: C) puts cee.c; end
    r { "a" || "b"}
    EOF

    assert_run_output("a\n", cls)
  end

  def test_two_closures_in_the_same_method
    cls, = compile(<<-EOF)
      def foo(a: Runnable)
        a.run
      end
      def regular: String
        foo { puts "Closure!" }
        foo { puts "We Want it" }
        "finish"
      end
      regular
    EOF
    assert_run_output("Closure!\nWe Want it\n", cls)
  end

  def test_closures_in_a_rescue
    cls, = compile(<<-EOF)
      def foo(a: Runnable)
        a.run
      end
      def regular: String
        begin
          foo { puts "Closure!" }
          raise "wut"
        rescue
          foo { puts "We Want it" }
        end
        "finish"
      end
      regular
    EOF
    assert_run_output("Closure!\nWe Want it\n", cls)
  end

  def test_lambda_with_type_defined_before
    cls, = compile(<<-EOF)
      interface Fooable
        def foo: void; end
      end
      x = lambda(Fooable) { puts "hey you" }
      x.foo
    EOF
    assert_run_output("hey you\n", cls)
  end

  def test_lambda_with_type_defined_later
    cls, = compile(<<-EOF)
      x = lambda(Fooable) { puts "hey you" }
      interface Fooable
        def foo: void; end
      end
      x.foo
    EOF
    assert_run_output("hey you\n", cls)
  end

  def test_closure_with_primitive_array_param
    cls, = compile(<<-EOF)
      interface Byter
        def byteme(bytes: byte[]): void; end
      end
      def r b: Byter
        b.byteme "yay".getBytes
      end
      r {|b| puts String.new(b) }
    EOF
    assert_run_output("yay\n", cls)
  end


  def test_block_syntax_for_anonymous_class_implementing_inner_interface
    cls, = compile('
      import org.foo.InnerInterfaceClass
      
      InnerInterfaceClass.forward("foo") do |param|
        puts param
      end
    ')
    assert_run_output("foo\n", cls)
  end

  def test_block_syntax_for_abstract_class_invoke_self
    omit_if JVMCompiler::JVM_VERSION.to_f < 1.8
    cls, = compile('
      import org.foo.AbstractExecutorJava8

      AbstractExecutorJava8.execute do
        puts "foo"
      end
    ')
    assert_run_output("foo\n", cls)
  end

  def test_lambda_closure
    cls, = compile(<<-EOF)
      def r b: Runnable
        b.run
      end
      msg = "yay"
      l = lambda(Runnable) { puts msg }
      r l
    EOF
    assert_run_output("yay\n", cls)
  end


  def test_binding_in_class_definition_has_right_namespace
    classes = compile(<<-'EOF')
      package test
      class Something
        def create(a: Runnable):void
          a.run
        end
        def with_binding
          loc = 1
          create do
            puts "test #{loc}"
          end
        end
      end
    EOF
    class_names = classes.map(&:java_class).map(&:name)
    pattern = /test\.Something\$.*?Binding\d*/
    assert class_names.find{|c| c.match pattern },
      "generated classes: #{class_names} didn't contain #{pattern}."
  end


  def test_binding_in_script_has_right_namespace
    classes = compile(<<-'EOF', name: 'MyScript')
      def create(a: Runnable):void
        a.run
      end
      def with_binding
        loc = 1
        create do
          puts "test #{loc}"
        end
      end
    EOF
    class_names = classes.map(&:java_class).map(&:name)
    pattern = /MyScriptTopLevel\$.*?Binding\d*/

    assert class_names.find{|c| c.match pattern },
      "generated classes: #{class_names} didn't contain #{pattern}."
  end


  def test_lambda_with_parameters
    cls, = compile(<<-EOF)
      abstract class Parametrized
        attr_reader arg: String
        def initialize(arg:int):void
          @arg = ""+arg
        end
        def initialize(arg:String):void
          @arg = arg
        end
        abstract def foo:void; end
      end
      x = lambda(Parametrized, 'foo') do
        puts arg + " foo"
      end
      x.foo
      y = lambda(Parametrized, 1) do
        puts arg + " foo"
      end
      y.foo
    EOF
    assert_run_output("foo foo\n1 foo\n", cls)
  end

  def test_single_outer_methods
    cls, = compile(%q[
package closure
class OuterTest1
  attr_reader attr: int

  def initialize
    @attr = 1
  end

  def run_code code:Runnable
    code.run
  end

  def test
    run_code do
      puts "foo: #{attr}"
    end
  end
end

OuterTest1.new.test
])
    assert_run_output("foo: 1\n", cls)
  end

  def test_lambda_outer_methods

  end

  def test_nested_outer_methods
    cls, = compile(%q[
package closure
class OuterTest2
  attr_reader attr1: int
  attr_reader attr2: int

  def initialize
    @attr1 = 1
    @attr2 = 2
  end

  def run_code code:Runnable
    code.run
  end

  def test
    run_code do
      puts "n1: #{attr1}"
      run_code do
        puts "n11: #{attr2}"
      end
      run_code do
        puts "n12: #{attr2}"
        run_code do
          puts "n121: #{attr2}"
        end
      end
    end
    run_code do
      puts "n2: #{attr1}"
      run_code do
        puts "n21: #{attr2}"
      end
      run_code do
        puts "n21: #{attr2}"
      end
    end
  end
end

OuterTest2.new.test
])
    assert_run_output("n1: 1\nn11: 2\nn12: 2\nn121: 2\nn2: 1\nn21: 2\nn21: 2\n", cls)
  end

  def test_outer_methods_in_script
    pend "ability define methods in script" do
    cls, = compile(%q[
package closure
class OuterRaiseTest1

run_code do
      puts "foo: #{attr}"
end

])
    assert_run_output("foo: 1\n", cls)
    end
  end

  def test_static_outer_access_instance_methods
    exception = assert_raises Mirah::MirahError do
      compile(%q[
package closure

class OuterRisesTest1

  attr_reader attr: int

  def initialize
    @attr = 1
  end

  def self.run_code code:Runnable
    code.run
  end

  def self.test
    run_code do
      puts "foo: #{attr}"
    end
  end
end])
    end
    assert_equal 'Undefined variable attr',
                 exception.message
  end

  def test_static_outer_methods
    cls, = compile(%q[
package closure
class StaticOuterTest1
  def self.attr1
    1
  end

  def self.attr2
    2
  end

  def self.run_code code:Runnable
    code.run
  end

  def self.test
    run_code do
      puts "n1: #{attr1}"
      run_code do
        puts "n11: #{attr2}"
      end
      run_code do
        puts "n12: #{attr2}"
        run_code do
          puts "n121: #{attr2}"
        end
      end
    end
    run_code do
      puts "n2: #{attr1}"
      run_code do
        puts "n21: #{attr2}"
      end
      run_code do
        puts "n21: #{attr2}"
      end
    end
  end
end

StaticOuterTest1.new.test
])
    assert_run_output("n1: 1\nn11: 2\nn12: 2\nn121: 2\nn2: 1\nn21: 2\nn21: 2\n", cls)
  end

  def test_explicit_nil_in
    cls, = compile(' [nil].each { |v| puts "#{v} => OK" }')
    assert_run_output("null => OK\n", cls)
  end

  def test_block_params_from_generics
    omit_if JVMCompiler::JVM_VERSION.to_f < 1.8 do
      cls, = compile('["a", "ab", "abc"].forEach { |v| puts v.length }')
      assert_run_output("1\n2\n3\n", cls)
    end
  end

  def test_block_params_from_generics_on_mirah_type
    omit_if JVMCompiler::JVM_VERSION.to_f < 1.8 do
      cls, = compile('
      class X
        def initialize(name:String); @name = name; end
        attr_reader name: String
      end
      [X.new("a"), X.new("ab"), X.new("abc")].forEach { |v| puts v.name }'
      )
      assert_run_output("a\nab\nabc\n", cls)
    end
  end

  def test_block_params_from_generics_on_stream_api
    omit_if JVMCompiler::JVM_VERSION.to_f < 1.8 do
      cls, = compile('puts ["a","b", "cc", "dd"].stream.filter { |s| s.length > 1 }.count')
      assert_run_output("2\n", cls)
    end
  end

  def test_block_params_infered_from_method_params

    cls, = compile('import java.util.List
        # from fixtures
        import org.infer.*

        class MyModel implements Model
          def initialize; @values = [1,2,3,4]; end
          # Model method
          def valueAt(row: int); @values[row]; end
          # custom method
          def values(list:List); @values = list; end
        end

        model = ModelFactory.model MyModel.class do |m|
          m.values [3,4,5,6]
        end

        puts model.valueAt(0)
        puts model.valueAt(1)
        puts model.valueAt(2)
    ')
    assert_run_output("3\n4\n5\n", cls)
  end

  # nested nlr scopes

# works with script as end
  # non-local-return when return type incompat, has sensible error
  # non-local-return when multiple non-local-return blocks in same method
  # non-local-return when multiple non-local-return blocks in same method, in if statment
  # non-local-return when multiple non-local-return block with multiple returns
  #    
end
