import'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:measurements/metadata/repository/metadata_repository.dart';
import 'package:measurements/util/logger.dart';
import 'package:measurements/util/size.dart';

import 'metadata_event.dart';
import 'metadata_state.dart';

class MetadataBloc extends Bloc<MetadataEvent, MetadataState> {
  final _logger = Logger(LogDistricts.METADATA_BLOC);
  final _initialMeasure = false;
  final _initialMagnificationRadius = magnificationRadius;

  bool _lastMeasure;
  double _lastMagnificationRadius;

  MetadataRepository _repository;

  MetadataBloc() {
    _repository = GetIt.I<MetadataRepository>();

    _repository.magnificationRadius.listen((double magnificationRadius) {
      _lastMagnificationRadius = magnificationRadius;
      add(MetadataUpdatedEvent(_lastMeasure ?? _initialMeasure, magnificationRadius));
    });
    _repository.measurement.listen((bool measure) {
      _lastMeasure = measure;
      add(MetadataUpdatedEvent(measure, _lastMagnificationRadius ?? _initialMagnificationRadius));
    });

    _logger.log("Created Bloc");
  }

  @override
  MetadataState get initialState => MetadataState(_initialMeasure, _initialMagnificationRadius);

  @override
  void onEvent(MetadataEvent event) {
    _logger.log("received event: $event");

    if (event is MetadataStartedEvent) {
      _repository.registerStartupValuesChange(
          event.measure,
          event.showDistances,
          event.callback,
          event.scale,
          event.zoom,
          event.documentSize
      );
    } else if (event is MetadataBackgroundEvent) {
      _repository.registerBackgroundChange(event.backgroundImage, event.size);
    }

    super.onEvent(event);
  }

  @override
  Stream<MetadataState> mapEventToState(MetadataEvent event) async* {
    if (event is MetadataUpdatedEvent) {
      yield MetadataState(event.measure, event.magnificationRadius);
    }
  }
}