# Copyright (c) 2012 The Mirah project authors. All Rights Reserved.
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

package org.mirah.builtins

import mirah.lang.ast.*

import org.mirah.macros.anno.ExtensionsRegistration

$ExtensionsRegistration[['java.lang.Enum']]
# override equals to be === for enums
class EnumExtensions

  macro def ==(node)
    # During the transition, alias == to === inside equals method definitions
    mdef = @call.findAncestor(MethodDefinition.class):MethodDefinition
    if mdef && mdef.name.identifier.equals("equals")
      if @call.target.kind_of?(Self) || node.kind_of?(Self)
        System.out.println("WARNING: == is now an alias for Object#equals(), === is now used for identity.\nThis use of == with self in equals() definition may cause a stack overflow in next release!#{mdef.position.source.name}:")
        source = @mirah.typer.sourceContent(mdef)
        s = source.split("\n")
        # last end has right whitespace, but def doesn't
        whitespace = s[s.length - 1].substring(0, s[s.length - 1].indexOf("end"))
        System.out.println("#{whitespace}#{source}")
        return quote {`@call.target` === `node`}
      end
    end

    left  = gensym
    right = gensym
    quote do
      `left`  = `@call.target`
      `right` = `node`
      `left` === `right`
    end
  end

  ## TODO handle the negation st def == will be called
  macro def !=(node)
    # TODO this doesn't work, but should
    #quote { ( `@call.target`.nil? && `node`.nil? ) || !`@call.target`.equals(`node`) }

    quote { !(`@call.target` == `node`)}
  end

end
