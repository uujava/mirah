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

require 'test_helper'

class NumericOperatorsTest < Test::Unit::TestCase

  OPERATORS = ['+', '-', '/', '*', '%', '>', '<', '!=', '==', '>=', '<=']
  # Note! signed right shift is not supported due to parser issue:
  # macro def >>>(n);end
  # wont parse
  BITWISE_OPERATORS = ['&', '|', '&', '^']
  SHIFT_OPERATORS = ['>>', '<<']
  # mirah fixnum constants defaults to int
  FIXNUM_TYPES = ['Integer', 'Short', 'Byte', 'Long']
  # need to cast constants to primitives
  FLOAT_TYPES = ['Float', 'Double']

  def self.define_test_methods(cast, i, numeric_class, operator , assert)
    define_method "test_#{numeric_class}_left_arithmetic_#{i}".to_sym do
      cls, = compile(<<-EOF)
          puts #{numeric_class}.new(5:#{cast}) #{operator} 7:#{cast}
      EOF
      assert_run_output("#{assert}\n", cls)
    end
    define_method "test_#{numeric_class}_right_arithmetic_#{i}".to_sym do
      cls, = compile(<<-EOF)
          puts 5:#{cast} #{operator} #{numeric_class}.new(7:#{cast})
      EOF
      assert_run_output("#{assert}\n", cls)
    end
  end

  def self.define_shift_test_methods(cast, i, numeric_class, operator , assert)
    define_method "test_#{numeric_class}_left_arithmetic_#{i}".to_sym do
      cls, = compile(<<-EOF)
          puts #{numeric_class}.new(5:#{cast}) #{operator} 7
      EOF
      assert_run_output("#{assert}\n", cls)
    end
    define_method "test_#{numeric_class}_right_arithmetic_#{i}".to_sym do
      cls, = compile(<<-EOF)
          puts 5 #{operator} #{numeric_class}.new(7:#{cast}).intValue
      EOF
      assert_run_output("#{assert}\n", cls)
    end
  end


  def self.define_cast_test_methods(numeric_class, primitive_class)
    str = <<-EOF
          a:#{numeric_class} = 5:#{primitive_class}
          puts "\#{a:int}\#{a.class.getName}"
    EOF
    puts str

    define_method "test_#{numeric_class}_cast_#{primitive_class}".to_sym do
      cls, = compile(str)
      assert_run_output("5java.lang.#{numeric_class}\n", cls)
    end
  end

  FIXNUM_TYPES.each do |numeric_class|
    test_num = 0
    cast = ('Integer' == numeric_class ? 'int' : numeric_class.downcase)
    (OPERATORS + BITWISE_OPERATORS).each do |operator|
      assert = eval "5#{operator}7"
      define_test_methods(cast, test_num+=1, numeric_class, operator, assert)
    end
    SHIFT_OPERATORS.each do |operator|
      assert = eval "5#{operator}7"
      define_shift_test_methods(cast, test_num+=1, numeric_class, operator, assert)
    end
  end

  # have to
  FLOAT_TYPES.each do |numeric_class|
    cast = numeric_class.downcase
    OPERATORS.each_with_index do |operator, i|
      assert = eval "5.0#{operator}7.0"
      if numeric_class == 'Float' and operator == '/'
        assert = '0.71428573'
      end
      define_test_methods(cast, i, numeric_class, operator, assert)
    end
  end

  (FIXNUM_TYPES+FLOAT_TYPES).each do |numeric_class|
    (FIXNUM_TYPES+FLOAT_TYPES).each do |primitive_class|
      primitive_class = ('Integer' == primitive_class ? 'int' : primitive_class.downcase)
      define_cast_test_methods(numeric_class, primitive_class)
    end
  end
end