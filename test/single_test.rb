# Copyright (c) 2010-2013 The Mirah project authors. All Rights Reserved.
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
require ENV.fetch('MIRAHC_JAR',File.expand_path("../../../dist/mirahc.jar",__FILE__))
require File.expand_path("../../jvm/new_backend_test_helper",__FILE__)

class SingleTest < Test::Unit::TestCase

  def test_deep_nested_runnable_with_binding
    cls, = compile(%q{
         puts 1
    })
    assert_run_output("1\n", cls)
  end

end

