package org.foo

import org.mirah.macros.anno.*
import org.mirah.macros.ExtensionsProvider
import org.mirah.macros.ExtensionsService


$ExtensionsRegistration[['java.lang.String']]
class PriorityMacro3Fixture
  macro def xxx_macro
    quote do
      puts "xxx3"
    end
  end
end