package org.mirah.util

import javax.tools.Diagnostic
import javax.tools.Diagnostic.Kind
import mirah.lang.ast.Position

class MirahDiagnostic implements Diagnostic
  def initialize(kind:Kind, position:Position, message:String)
    @kind = kind
    @position = position
    @message = message
  end
  
  def self.error(position:Position, message:String)
    MirahDiagnostic.new(Kind.ERROR, position, message)
  end
  
  def self.warning(position:Position, message:String)
    MirahDiagnostic.new(Kind.WARNING, position, message)
  end
  
  def self.note(position:Position, message:String)
    MirahDiagnostic.new(Kind.NOTE, position, message)
  end
  
  def getKind
    @kind
  end
  
  def getMessage(locale)
    @message
  end
  
  def getSource
    @position.source if @position
  end
  
  #TODO
  def getCode; nil; end
  
  def getColumnNumber:long
    if @position
      (@position.startColumn):long
    else
      Diagnostic.NOPOS
    end
  end
  
  def getEndPosition:long
    if @position
      (@position.endChar):long
    else
      Diagnostic.NOPOS
    end
  end
  
  def getLineNumber:long
    if @position
      (@position.startLine):long
    else
      Diagnostic.NOPOS
    end
  end
  
  def getPosition:long
    if @position
      (@position.startChar):long
    else
      Diagnostic.NOPOS
    end
  end
  
  def getStartPosition:long
    getPosition
  end
end