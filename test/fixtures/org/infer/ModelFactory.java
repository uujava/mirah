package org.infer;

import java.lang.Object;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;

public class ModelFactory {

    // test M iferred from Model class
    public static <M extends Model> M model(Class<M> clazz, ModelBuilder<M> builder) throws Throwable {
        M model = clazz.newInstance();
        builder.accept(model);
        return model;
    }

}
