package org.mirah.typer.closures

import mirah.lang.ast.NodeScanner
import mirah.lang.ast.Node
import mirah.lang.ast.TypeRefImpl

#replaces $outer  FieldAccess to Type call
class StaticOuterAdjuster  < NodeScanner
  def initialize(data:OuterData)
    @data = data
    raise IllegalStateException.new("outer data is not from meta scope #{data}") unless data.is_meta
  end

  def adjust(block:Node):void
    block.accept self, nil
  end

  def enterFieldAccess(field, blah)
    if field.name.identifier == '$outer'
      parent = field.parent
      parent.replaceChild(field, TypeRefImpl.new(@data.outer_type.name, false, false, field.position))
    end
    false
  end

end