///
/// Copyright (c) 2020 arconsis IT-Solutions GmbH
/// Licensed under MIT (https://github.com/arconsis/measurements/blob/master/LICENSE)
///

import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:measurements/measurement/drawing_holder.dart';
import 'package:measurements/measurements.dart';
import 'package:measurements/metadata/repository/metadata_repository.dart';
import 'package:measurements/util/logger.dart';
import 'package:measurements/util/utils.dart';
import 'package:rxdart/rxdart.dart';

enum TouchState {
  FREE,
  DOWN,
  MOVE,
  UP,
}

class MeasurementRepository {
  final _logger = Logger(LogDistricts.MEASUREMENT_REPOSITORY);

  final _points = BehaviorSubject<List<Offset>>.seeded(List());
  final _distances = BehaviorSubject<List<LengthUnit>>.seeded(List());
  final _drawingHolder = BehaviorSubject<DrawingHolder>();
  final MetadataRepository _metadataRepository;

  MeasurementController _controller;
  LengthUnit _transformationFactor;
  double _imageToDocumentScaleFactor = 1.0;

  int _currentIndex = -1;
  TouchState _currentState = TouchState.FREE;

  List<Offset> _absolutePoints = List();
  double _zoomLevel = 1.0;
  Offset _backgroundPosition = Offset(0, 0);
  Offset _viewCenterPosition = Offset(0, 0);

  MeasurementRepository(this._metadataRepository) {
    _metadataRepository.controller.listen((controller) => _controller = controller);
    _metadataRepository.viewCenter.listen((viewCenter) => _viewCenterPosition = viewCenter);
    _metadataRepository.imageToDocumentScaleFactor.listen((scaleFactor) {
      _imageToDocumentScaleFactor = scaleFactor;
      _publishPoints();
    });
    _metadataRepository.transformationFactor.listen((factor) {
      if (_transformationFactor != factor) {
        _transformationFactor = factor;
        _synchronizeDistances();
      }
    });
    _metadataRepository.zoom.listen((zoom) {
      _zoomLevel = zoom;
      _publishPoints();
    });
    _metadataRepository.backgroundPosition.listen((backgroundPosition) {
      _backgroundPosition = Offset(backgroundPosition.dx, -backgroundPosition.dy);
      _publishPoints();
    });
  }

  Stream<List<Offset>> get points => _points.stream;

  Stream<DrawingHolder> get drawingHolder => _drawingHolder.stream;

  void registerDownEvent(Offset globalPosition) {
    if (_currentState != TouchState.FREE) return;
    _currentState = TouchState.DOWN;

    Offset documentLocalCenteredPosition = _convertIntoDocumentLocalCenteredPosition(globalPosition, _viewCenterPosition);

    int closestIndex = _getClosestPointIndex(documentLocalCenteredPosition);

    if (closestIndex >= 0) {
      Offset closestPoint = _absolutePoints[closestIndex];

      if ((_convertIntoGlobalPosition(closestPoint, _viewCenterPosition) - globalPosition).distance > 40.0) {
        _currentIndex = _addNewPoint(documentLocalCenteredPosition);
      } else {
        _currentIndex = closestIndex;
        _updatePoint(documentLocalCenteredPosition);
      }
    } else {
      _currentIndex = _addNewPoint(documentLocalCenteredPosition);
    }

    _movementStarted(_currentIndex);
  }

  void registerMoveEvent(Offset position) {
    if (_currentState != TouchState.DOWN && _currentState != TouchState.MOVE) return;
    _currentState = TouchState.MOVE;

    _updatePoint(_convertIntoDocumentLocalCenteredPosition(position, _viewCenterPosition));
  }

  void registerUpEvent(Offset position) {
    if (_currentState != TouchState.DOWN && _currentState != TouchState.MOVE) return;
    _currentState = TouchState.UP;

    _updatePoint(_convertIntoDocumentLocalCenteredPosition(position, _viewCenterPosition));
    _movementFinished();
  }

  void removeCurrentPoint() {
    if (_currentIndex >= 0) {
      _absolutePoints.removeAt(_currentIndex);
      _publishPoints();

      _movementFinished();
    }
  }

  void dispose() {
    _points.close();
    _distances.close();
    _drawingHolder.close();
  }

  Offset convertIntoDocumentLocalTopLeftPosition(Offset position) {
    Offset documentLocalCenterPosition = _convertIntoDocumentLocalCenteredPosition(position, _viewCenterPosition) / _imageToDocumentScaleFactor;

    return Offset(documentLocalCenterPosition.dx + _viewCenterPosition.dx, _viewCenterPosition.dy - documentLocalCenterPosition.dy);
  }

  Offset _convertIntoDocumentLocalCenteredPosition(Offset position, Offset viewCenter) {
    return (Offset(position.dx - viewCenter.dx, viewCenter.dy - position.dy) - _backgroundPosition) / _zoomLevel * _imageToDocumentScaleFactor;
  }

  Offset _convertIntoGlobalPosition(Offset position, Offset viewCenter) {
    Offset scaledPosition = position / _imageToDocumentScaleFactor * _zoomLevel;

    return Offset(scaledPosition.dx + viewCenter.dx + _backgroundPosition.dx, viewCenter.dy - scaledPosition.dy - _backgroundPosition.dy);
  }

  List<Offset> _getRelativePoints() {
    return _absolutePoints.map((point) => _convertIntoGlobalPosition(point, _viewCenterPosition)).toList();
  }

  void _publishPoints() {
    List<Offset> relativePoints = _getRelativePoints();

    _logger.log("\nimageToDocumentScaleFactor: ${_imageToDocumentScaleFactor.toStringAsFixed(2)}, "
        "zoomLevel: ${_zoomLevel.toStringAsFixed(2)}, "
        "backgroundPosition: $_backgroundPosition, "
        "viewCenter: $_viewCenterPosition\n"
        "absolute points: $_absolutePoints\n"
        "relative points: $relativePoints");

    _points.add(relativePoints);
    _drawingHolder.add(DrawingHolder(relativePoints, _distances.value));
  }

  int _addNewPoint(Offset point) {
    _absolutePoints.add(point);
    _publishPoints();

    _logger.log("added point: $_absolutePoints");
    return _absolutePoints.length - 1;
  }

  void _updatePoint(Offset point) {
    if (_currentIndex >= 0) {
      _absolutePoints.setRange(_currentIndex, _currentIndex + 1, [point]);
      _publishPoints();

      _logger.log("updated point $_currentIndex: $_absolutePoints");
    }
  }

  int _getClosestPointIndex(Offset reference) {
    int index = 0;

    List<_CompareHolder> sortedPoints = _absolutePoints.map((Offset point) => _CompareHolder(index++, (reference - point).distance)).toList();

    sortedPoints.sort((_CompareHolder a, _CompareHolder b) => a.distance.compareTo(b.distance));

    return sortedPoints.length > 0 ? sortedPoints[0].index : -1;
  }

  void _publishDistances(List<LengthUnit> distances) {
    _distances.add(distances);
    _drawingHolder.add(DrawingHolder(_getRelativePoints(), distances));
  }

  void _movementStarted(int index) {
    List<LengthUnit> distances = List()..addAll(_distances.value);

    distances.setRange(max(0, index - 1), min(distances.length, index + 1), [null, null]);
    _publishDistances(distances);

    _logger.log("started moving point with index: $index");
  }

  void _movementFinished() {
    _currentIndex = -1;
    _synchronizeDistances();
    _currentState = TouchState.FREE;
  }

  void _synchronizeDistances() {
    if (_transformationFactor != null && _absolutePoints.length >= 2) {
      List<LengthUnit> distances = List();
      _absolutePoints.doInBetween((start, end) => distances.add(_transformationFactor * (start - end).distance));
      _publishDistances(distances);

      _controller?.distances = distances.map((unit) => unit.value).toList();
    } else if (_absolutePoints.length == 1) {
      _publishDistances([]);
      _controller?.distances = [];
    }
  }
}

class _CompareHolder {
  double distance;
  int index;

  _CompareHolder(this.index, this.distance);
}
