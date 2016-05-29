package org.foo

import org.mirah.macros.anno.*
import org.mirah.macros.ExtensionsProvider
import org.mirah.macros.ExtensionsService


$ExtensionsRegistration[['java.lang.String']]
class PriorityMacroProvider implements ExtensionsProvider

  def register(type_system:ExtensionsService):void
    type_system.macro_registration(PriorityMacro1Fixture.class)
    type_system.macro_registration(PriorityMacro2Fixture.class)
    type_system.macro_registration(PriorityMacro3Fixture.class)
  end

end