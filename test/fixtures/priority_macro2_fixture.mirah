package org.foo

import org.mirah.macros.anno.*
import org.mirah.macros.ExtensionsProvider
import org.mirah.macros.ExtensionsService


$ExtensionsRegistration[['java.lang.String']]
class PriorityMacro2Fixture

  $Priority[10]
  macro def xxx_macro
    quote do
      puts "xxx2"
    end
  end

end