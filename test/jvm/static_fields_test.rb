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

class StaticFieldsTest < Test::Unit::TestCase
  def test_static_field_inheritance_lookup_with_dot
    cls, = compile(<<-EOF)
      import java.util.GregorianCalendar
      puts GregorianCalendar.AM
    EOF

    assert_run_output("0\n", cls)
  end

  def test_static_field_inheritance_lookup_with_double_colon
    return
    pend("double colon is treated special for lookup") {
    cls, = compile(<<-EOF)
      import java.util.GregorianCalendar
      puts GregorianCalendar::AM
    EOF

    assert_run_output("0\n", cls)
    }
  end

  def test_create_constant
    cls, = compile(<<-EOF)
      CONSTANT = 1
      puts CONSTANT
    EOF
    assert_run_output("1\n", cls)
  end
end
