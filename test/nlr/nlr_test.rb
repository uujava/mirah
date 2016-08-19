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

class NlrBlocksTest < Test::Unit::TestCase

  def parse_and_type code, name=tmp_script_name
    parse_and_resolve_types name, code
  end

  def test_closures_support_non_local_return
    pend "nlr doesnt work right now" do
      cls, = compile(<<-EOF)
      class NonLocalMe
        def foo(a: Runnable)
          a.run
          puts "doesn't get here"
        end
      end
      def nlr: String
        NonLocalMe.new.foo { return "NLR!"}
        "nor here either"
      end
      puts nlr
      EOF
      assert_run_output("NLR!\n", cls)
    end
  end

  def test_closures_support_non_local_return_with_primitives
    pend "nlr doesnt work right now" do
      cls, = compile(<<-EOF)
      class NonLocalMe
        def foo(a: Runnable)
          a.run
          puts "doesn't get here"
        end
      end
      def nlr: int
        NonLocalMe.new.foo { return 1234}
        5678
      end
      puts nlr
      EOF
      assert_run_output("1234\n", cls)
    end
  end

  def test_when_non_local_return_types_incompatible_has_error
    error = assert_raises Mirah::MirahError do
      parse_and_type(<<-CODE)
      class NonLocalMe
        def foo(a: Runnable)
          a.run
          puts "doesn't get here"
        end
      end
      def nlr: int
        NonLocalMe.new.foo { return "not an int" }
        5678
      end

      CODE
    end
    pend "differing type signatures for nlr" do
      # could be better, if future knew it was a return type
      assert_equal "Invalid return type java.lang.String, expected int", error.message
    end
  end

  def test_closures_non_local_return_to_a_script
    pend "nlr doesnt work right now" do
      cls, = compile(<<-EOF)
      def foo(a: Runnable)
        a.run
        puts "doesn't get here"
      end
      puts "before"
      foo { return }
      puts "or here"
      EOF
      assert_run_output("before\n", cls)
    end
  end

  def test_closures_non_local_return_defined_in_a_class
    pend "nlr doesnt work right now" do
      cls, = compile(<<-EOF)
      class ClosureInMethodInClass
        def foo(a: Runnable)
          a.run
          puts "doesn't get here"
        end
        def nlr
          puts "before"
          foo { return 1234 }
          puts "or here"
          5678
        end
      end
      puts ClosureInMethodInClass.new.nlr
      EOF
      assert_run_output("before\n1234\n", cls)
    end
  end

  def test_closures_non_local_return_defined_in_a_void_method
    pend "nlr doesnt work right now" do
      cls, = compile(<<-EOF)
      class ClosureInVoidMethodInClass
        def foo(a: Runnable)
          a.run
          puts "doesn't get here"
        end
        def nlr: void
          puts "before"
          foo { return }
          puts "or here"
        end
      end
      ClosureInVoidMethodInClass.new.nlr
      EOF
      assert_run_output("before\n", cls)
    end
  end

  def test_closure_non_local_return_with_multiple_returns
    pend "nlr doesnt work right now" do
      cls, = compile(<<-EOF)
      class NLRMultipleReturnRunner
        def foo(a: Runnable)
          a.run
          puts "doesn't get here"
        end
      end
      def nlr(flag: boolean): String
        NLRMultipleReturnRunner.new.foo { if flag; return "NLR!"; else; return "NLArrrr"; end}
        "nor here either"
      end
      puts nlr true
      puts nlr false
      EOF
      assert_run_output("NLR!\nNLArrrr\n", cls)
    end
  end

  def test_two_nlr_closures_in_the_same_method_in_if
    pend "nlr doesnt work right now" do
      cls, = compile(<<-EOF)
      class NLRTwoClosure
        def foo(a: Runnable)
          a.run
          puts "doesn't get here"
        end
      end
      def nlr(flag: boolean): String
        if flag
          NLRTwoClosure.new.foo { return "NLR!" }
        else
          NLRTwoClosure.new.foo { return "NLArrrr" }
        end
        "nor here either"
      end
      puts nlr true
      puts nlr false
      EOF
      assert_run_output("NLR!\nNLArrrr\n", cls)
    end
  end

  def test_two_nlr_closures_in_the_same_method
    pend "nlr doesnt work right now" do
      # this has a binding generation problem
      cls, = compile(<<-EOF)
      class NonLocalMe2
        def foo(a: Runnable)
          a.run
          puts "may get here"
        end
      end
      def nlr(flag: boolean): String
        NonLocalMe2.new.foo { return "NLR!" if flag }
        NonLocalMe2.new.foo { return "NLArrrr" unless flag }
        "but not here"
      end
      puts nlr true
      puts nlr false
      EOF
      assert_run_output("NLR!\nmay get here\nNLArrrr\n", cls)
    end
  end
end