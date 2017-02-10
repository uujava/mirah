package org.infer;

import java.lang.Object;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;

public interface ModelBuilder<E> {

    void accept(E value);

}
